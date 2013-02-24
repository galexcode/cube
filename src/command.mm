// command.cpp: implements the parsing and execution of a tiny script language which
// is largely backwards compatible with the quake console language.

#include "cube.h"

enum { ID_VAR, ID_COMMAND, ID_ALIAS };

@interface Ident: OFObject
{
@public
	int _type;           // one of ID_* above
	char *_name;
	int _min, _max;      // ID_VAR
	int *_storage;       // ID_VAR
	void (*_fun)();      // ID_VAR, ID_COMMAND
	int _narg;           // ID_VAR, ID_COMMAND
	char *_action;       // ID_ALIAS
	bool _persist;
}

@property int *storage;
@end

@implementation Ident
@synthesize storage = _storage;
@end

void itoa(char *s, int i) { sprintf_s(s)("%d", i); };
char *exchangestr(char *o, char *n) { gp()->deallocstr(o); return newstring(n); };

static OFMutableDictionary *idents = nil;

void alias(char *name, char *action)
{
	void *pool = objc_autoreleasePoolPush();
	Ident *b = idents[@(name)];

	if (b == nil) {
		b = [[Ident new] autorelease];
		b->_type = ID_ALIAS;
		b->_name = newstring(name);
		b->_action = newstring(action);
		b->_persist = true;

		idents[@(name)] = b;
	} else {
		if (b->_type == ID_ALIAS)
			b->_action = exchangestr(b->_action, action);
		else
			conoutf("cannot redefine builtin %s with an alias",
			    name);
	}

	objc_autoreleasePoolPop(pool);
}

COMMAND(alias, ARG_2STR);

// variable's and commands are registered through globals, see cube.h

int
variable(char *name, int min, int cur, int max, int *storage, void (*fun)(),
    bool persist)
{
	void *pool = objc_autoreleasePoolPush();

	if (idents == nil)
		idents = [OFMutableDictionary new];

	Ident *v = [[Ident new] autorelease];
	v->_type = ID_VAR;
	v->_name = name;
	v->_min = min;
	v->_max = max;
	v->_storage = storage;
	v->_fun = fun;
	v->_persist = true;

	idents[@(name)] = v;

	objc_autoreleasePoolPop(pool);

	return cur;
}

void
setvar(char *name, int i)
{
	void *pool = objc_autoreleasePoolPush();

	*[idents[@(name)] storage] = i;

	objc_autoreleasePoolPop(pool);
}

int
getvar(char *name)
{
	void *pool = objc_autoreleasePoolPush();
	int v;

	v = *[idents[@(name)] storage];

	objc_autoreleasePoolPop(pool);

	return v;
}

bool
identexists(char *name)
{
	void *pool = objc_autoreleasePoolPush();
	bool e;

	e = ([idents[@(name)] storage] != nil);

	objc_autoreleasePoolPop(pool);

	return e;
}

char*
getalias(char *name)
{
	void *pool = objc_autoreleasePoolPush();
	char *ret = NULL;
	Ident *i;

	if ((i = idents[@(name)]) != nil && i->_type == ID_ALIAS)
		ret = i->_action;

	objc_autoreleasePoolPop(pool);

	return ret;
};

bool
addcommand(char *name, void (*fun)(), int narg)
{
	void *pool = objc_autoreleasePoolPush();

	if (idents == nil)
		idents = [OFMutableDictionary new];

	Ident *c = [[Ident new] autorelease];
	c->_type = ID_COMMAND;
	c->_name = name;
	c->_fun = fun;
	c->_narg = narg;

	idents[@(name)] = c;

	objc_autoreleasePoolPop(pool);

	return false;
}

char *parseexp(char *&p, int right)             // parse any nested set of () or []
{
    int left = *p++;
    char *word = p;
    for(int brak = 1; brak; )
    {
        int c = *p++;
        if(c=='\r') *(p-1) = ' ';               // hack
        if(c==left) brak++;
        else if(c==right) brak--;
        else if(!c) { p--; conoutf("missing \"%c\"", right); return NULL; };
    };
    char *s = newstring(word, p-word-1);
    if(left=='(')
    {
        string t;
        itoa(t, execute(s));                    // evaluate () exps directly, and substitute result
        s = exchangestr(s, t);
    };
    return s;
};

char *parseword(char *&p)                       // parse single argument, including expressions
{
    p += strspn(p, " \t\r");
    if(p[0]=='/' && p[1]=='/') p += strcspn(p, "\n\0");
    if(*p=='\"')
    {
        p++;
        char *word = p;
        p += strcspn(p, "\"\r\n\0");
        char *s = newstring(word, p-word);
        if(*p=='\"') p++;
        return s;
    };
    if(*p=='(') return parseexp(p, ')');
    if(*p=='[') return parseexp(p, ']');
    char *word = p;
    p += strcspn(p, "; \t\r\n\0");
    if(p-word==0) return NULL;
    return newstring(word, p-word);
};

// find value of ident referenced with $ in exp
char
*lookup(char *n)
{
	void *pool = objc_autoreleasePoolPush();
	Ident *i;

	if ((i = idents[@(n + 1)]) != nil) {
		objc_autoreleasePoolPop(pool);

		switch (i->_type) {
		case ID_VAR:
			string t;
			itoa(t, *(i->_storage));
			return exchangestr(n, t);
		case ID_ALIAS:
			return exchangestr(n, i->_action);
		}
	}

	conoutf("unknown alias lookup: %s", n+1);

	objc_autoreleasePoolPop(pool);

	return n;
}

int execute(char *p, bool isdown)               // all evaluation happens here, recursively
{
    const int MAXWORDS = 25;                    // limit, remove
    char *w[MAXWORDS];
    int val = 0;
    for(bool cont = true; cont;)                // for each ; seperated statement
    {
        int numargs = MAXWORDS;
        loopi(MAXWORDS)                         // collect all argument values
        {
            w[i] = "";
            if(i>numargs) continue;
            char *s = parseword(p);             // parse and evaluate exps
            if(!s) { numargs = i; s = ""; };
            if(*s=='$') s = lookup(s);          // substitute variables
            w[i] = s;
        };

        p += strcspn(p, ";\n\0");
        cont = *p++!=0;                         // more statements if this isn't the end of the string
        char *c = w[0];
        if(*c=='/') c++;                        // strip irc-style command prefix
        if(!*c) continue;                       // empty statement

	void *pool = objc_autoreleasePoolPush();
	Ident *i;
	if ((i = idents[@(c)]) == nil) {
		val = ATOI(c);
		if (!val && *c != '0')
			conoutf("unknown command: %s", c);
        } else
		switch(i->_type) {
            case ID_COMMAND:                    // game defined commands
                switch(i->_narg)                // use very ad-hoc function signature, and just call it
                {
                    case ARG_1INT: if(isdown) ((void (__cdecl *)(int))i->_fun)(ATOI(w[1])); break;
                    case ARG_2INT: if(isdown) ((void (__cdecl *)(int, int))i->_fun)(ATOI(w[1]), ATOI(w[2])); break;
                    case ARG_3INT: if(isdown) ((void (__cdecl *)(int, int, int))i->_fun)(ATOI(w[1]), ATOI(w[2]), ATOI(w[3])); break;
                    case ARG_4INT: if(isdown) ((void (__cdecl *)(int, int, int, int))i->_fun)(ATOI(w[1]), ATOI(w[2]), ATOI(w[3]), ATOI(w[4])); break;
                    case ARG_NONE: if(isdown) ((void (__cdecl *)())i->_fun)(); break;
                    case ARG_1STR: if(isdown) ((void (__cdecl *)(char *))i->_fun)(w[1]); break;
                    case ARG_2STR: if(isdown) ((void (__cdecl *)(char *, char *))i->_fun)(w[1], w[2]); break;
                    case ARG_3STR: if(isdown) ((void (__cdecl *)(char *, char *, char*))i->_fun)(w[1], w[2], w[3]); break;
                    case ARG_5STR: if(isdown) ((void (__cdecl *)(char *, char *, char*, char*, char*))i->_fun)(w[1], w[2], w[3], w[4], w[5]); break;
                    case ARG_DOWN: ((void (__cdecl *)(bool))i->_fun)(isdown); break;
                    case ARG_DWN1: ((void (__cdecl *)(bool, char *))i->_fun)(isdown, w[1]); break;
                    case ARG_1EXP: if(isdown) val = ((int (__cdecl *)(int))i->_fun)(execute(w[1])); break;
                    case ARG_2EXP: if(isdown) val = ((int (__cdecl *)(int, int))i->_fun)(execute(w[1]), execute(w[2])); break;
                    case ARG_1EST: if(isdown) val = ((int (__cdecl *)(char *))i->_fun)(w[1]); break;
                    case ARG_2EST: if(isdown) val = ((int (__cdecl *)(char *, char *))i->_fun)(w[1], w[2]); break;
                    case ARG_VARI: if(isdown)
                    {
                        string r;               // limit, remove
                        r[0] = 0;
                        for(int i = 1; i<numargs; i++)
                        {
                            strcat_s(r, w[i]);  // make string-list out of all arguments
                            if(i==numargs-1) break;
                            strcat_s(r, " ");
                        };
                        ((void (__cdecl *)(char *))i->_fun)(r);
                        break;
                    }
                };
                break;

            case ID_VAR:                        // game defined variabled
                if(isdown)
                {
                    if(!w[1][0]) conoutf("%s = %d", c, *i->_storage);      // var with no value just prints its current value
                    else
                    {
                        if(i->_min>i->_max)
                        {
                            conoutf("variable is read-only");
                        }
                        else
                        {
                            int i1 = ATOI(w[1]);
                            if(i1 < i->_min || i1> i->_max)
                            {
                                i1 = i1<i->_min ? i->_min : i->_max;                // clamp to valid range
                                conoutf("valid range for %s is %d..%d", c, i->_min, i->_max);
                            }
                            *i->_storage = i1;
                        };
                        if(i->_fun) ((void (__cdecl *)())i->_fun)();            // call trigger function if available
                    };
                };
                break;

            case ID_ALIAS:                              // alias, also used as functions and (global) variables
                for(int i = 1; i<numargs; i++)
                {
                    sprintf_sd(t)("arg%d", i);          // set any arguments as (global) arg values so functions can access them
                    alias(t, w[i]);
                };
                char *action = newstring(i->_action);   // create new string here because alias could rebind itself
                val = execute(action, isdown);
                gp()->deallocstr(action);
                break;
        };
	objc_autoreleasePoolPop(pool);
        loopj(numargs) gp()->deallocstr(w[j]);
    }
    return val;
};

// tab-completion of all idents

int completesize = 0, completeidx = 0;

void resetcomplete() { completesize = 0; };

void complete(char *s)
{
	if (*s != '/') {
		string t;
		strcpy_s(t, s);
		strcpy_s(s, "/");
		strcat_s(s, t);
	}

	if (s[1] == 0)
		return;

	if (completesize == 0) {
		completesize = (int)strlen(s) - 1;
		completeidx = 0;
	}

	int idx = 0;
	for (OFString *key in idents) {
		const char *name = [key UTF8String];

		if (strncmp(name, s + 1, completesize) == 0 &&
		    idx++ == completeidx) {
			strcpy_s(s, "/");
			strcat_s(s, name);
		}
	}

	if (++completeidx >= idx)
		completeidx = 0;
}

bool execfile(char *cfgfile)
{
    string s;
    strcpy_s(s, cfgfile);
    char *buf = loadfile(path(s), NULL);
    if(!buf) return false;
    execute(buf);
    free(buf);
    return true;
};

void exec(char *cfgfile)
{
    if(!execfile(cfgfile)) conoutf("could not read \"%s\"", cfgfile);
};

void writecfg()
{
	FILE *f = fopen("config.cfg", "w");
	if (f == NULL)
		return;
	fprintf(f, "// automatically written on exit, do not modify\n// delete this file to have defaults.cfg overwrite these settings\n// modify settings in game, or put settings in autoexec.cfg to override anything\n\n");
	writeclientinfo(f);
	fprintf(f, "\n");

	[idents enumerateKeysAndObjectsUsingBlock:
	    ^ (OFString *name, Ident *i, BOOL *stop) {
		if (i->_type == ID_VAR && i->_persist)
			fprintf(f, "%s %d\n", i->_name, *i->_storage);
	}];
	fprintf(f, "\n");
	writebinds(f);
	fprintf(f, "\n");

	[idents enumerateKeysAndObjectsUsingBlock:
	    ^ (OFString *name, Ident *i, BOOL *stop) {
		if (i->_type == ID_ALIAS && ![name hasPrefix: @"nextmap_"])
			fprintf(f, "alias \"%s\" [%s]\n", i->_name, i->_action);
	}];

	fclose(f);
}

COMMAND(writecfg, ARG_NONE);

// below the commands that implement a small imperative language. thanks to the semantics of
// () and [] expressions, any control construct can be defined trivially.

void intset(char *name, int v) { string b; itoa(b, v); alias(name, b); };

void ifthen(char *cond, char *thenp, char *elsep) { execute(cond[0]!='0' ? thenp : elsep); };
void loopa(char *times, char *body) { int t = atoi(times); loopi(t) { intset("i", i); execute(body); }; };
void whilea(char *cond, char *body) { while(execute(cond)) execute(body); };    // can't get any simpler than this :)
void onrelease(bool on, char *body) { if(!on) execute(body); };

void concat(char *s) { alias("s", s); };

void concatword(char *s)
{
    for(char *a = s, *b = s; *a = *b; b++) if(*a!=' ') a++;
    concat(s);
};

int listlen(char *a)
{
    if(!*a) return 0;
    int n = 0;
    while(*a) if(*a++==' ') n++;
    return n+1;
};

void at(char *s, char *pos)
{
    int n = atoi(pos);
    loopi(n) s += strspn(s += strcspn(s, " \0"), " ");
    s[strcspn(s, " \0")] = 0;
    concat(s);
};

COMMANDN(loop, loopa, ARG_2STR);
COMMANDN(while, whilea, ARG_2STR);
COMMANDN(if, ifthen, ARG_3STR);
COMMAND(onrelease, ARG_DWN1);
COMMAND(exec, ARG_1STR);
COMMAND(concat, ARG_VARI);
COMMAND(concatword, ARG_VARI);
COMMAND(at, ARG_2STR);
COMMAND(listlen, ARG_1EST);

int add(int a, int b)   { return a+b; };         COMMANDN(+, add, ARG_2EXP);
int mul(int a, int b)   { return a*b; };         COMMANDN(*, mul, ARG_2EXP);
int sub(int a, int b)   { return a-b; };         COMMANDN(-, sub, ARG_2EXP);
int divi(int a, int b)  { return b ? a/b : 0; }; COMMANDN(div, divi, ARG_2EXP);
int mod(int a, int b)   { return b ? a%b : 0; }; COMMAND(mod, ARG_2EXP);
int equal(int a, int b) { return (int)(a==b); }; COMMANDN(=, equal, ARG_2EXP);
int lt(int a, int b)    { return (int)(a<b); };  COMMANDN(<, lt, ARG_2EXP);
int gt(int a, int b)    { return (int)(a>b); };  COMMANDN(>, gt, ARG_2EXP);

int strcmpa(char *a, char *b) { return strcmp(a,b)==0; };  COMMANDN(strcmp, strcmpa, ARG_2EST);

int rndn(int a)    { return a>0 ? rnd(a) : 0; };  COMMANDN(rnd, rndn, ARG_1EXP);

int explastmillis() { return lastmillis; };  COMMANDN(millis, explastmillis, ARG_1EXP);

