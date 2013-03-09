// command.cpp: implements the parsing and execution of a tiny script language which
// is largely backwards compatible with the quake console language.

#include "cube.h"

enum { ID_VAR, ID_COMMAND, ID_ALIAS };

@interface Ident: OFObject
{
	int _type;           // one of ID_* above
	OFString *_name;
	int _min, _max;      // ID_VAR
	int *_storage;       // ID_VAR
	void (*_fun)();      // ID_VAR, ID_COMMAND
	int _narg;           // ID_VAR, ID_COMMAND
	OFString *_action;       // ID_ALIAS
	bool _persist;
}

@property int type;
@property (copy) OFString *name;
@property int min, max;
@property void (*fun)();
@property int *storage;
@property int narg;
@property (copy) OFString *action;
@property bool persist;
@end

@implementation Ident
@synthesize type = _type, name = _name, min = _min, max = _max, fun = _fun;
@synthesize storage = _storage, narg = _narg, action = _action;
@synthesize persist = _persist;
@end

void
itoa(char *s, int i)
{
	sprintf_s(s)("%d", i);
}

char*
exchangestr(char *o, const char *n)
{
	gp()->deallocstr(o);
	return newstring(n);
}

static OFMutableDictionary *idents = nil;

void alias(char *name, char *action)
{
	@autoreleasepool {
		Ident *b = idents[@(name)];

		if (b == nil) {
			b = [Ident new];
			b.type = ID_ALIAS;
			b.name = @(name);
			b.action = @(action);
			b.persist = true;

			idents[@(name)] = b;
		} else {
			if (b.type == ID_ALIAS)
				b.action = @(action);
			else
				conoutf("cannot redefine builtin %s with an "
				    "alias", name);
		}
	}
}

// variable's and commands are registered through globals, see cube.h

int
variable(OFString *name, int min, int cur, int max, int *storage, void (*fun)(),
    bool persist)
{
	if (idents == nil)
		idents = [OFMutableDictionary new];

	Ident *v = [Ident new];
	v.type = ID_VAR;
	v.name = name;
	v.min = min;
	v.max = max;
	v.storage = storage;
	v.fun = fun;
	v.persist = true;

	idents[name] = v;

	return cur;
}

void
setvar(OFString *name, int i)
{
	*[idents[name] storage] = i;
}

int
getvar(OFString *name)
{
	return *[idents[name] storage];
}

bool
identexists(OFString *name)
{
	return ([idents[name] storage] != NULL);
}

char*
getalias(char *name)
{
	@autoreleasepool {
		Ident *i = idents[@(name)];

		if (i.type == ID_ALIAS)
			/* FIXME: Evil cast as a temporary workaround */
			return (char*)[i.action UTF8String];
	}

	return NULL;
}

bool
addcommand(OFString *name, void (*fun)(), int narg)
{
	@autoreleasepool {
		if (idents == nil)
			idents = [OFMutableDictionary new];

		Ident *c = [Ident new];
		c.type = ID_COMMAND;
		c.name = name;
		c.fun = fun;
		c.narg = narg;

		idents[name] = c;
	}

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
	@autoreleasepool {
		Ident *i = idents[@(n + 1)];

		if (i != nil) {
			switch (i.type) {
			case ID_VAR:
				string t;
				itoa(t, *(i.storage));
				return exchangestr(n, t);
			case ID_ALIAS:
				return exchangestr(n, [i.action UTF8String]);
			}
		}
	}

	conoutf("unknown alias lookup: %s", n+1);

	return n;
}

// all evaluation happens here, recursively
int execute(char *p, bool isdown)
{
	const int MAXWORDS = 25;	// limit, remove
	char *w[MAXWORDS];
	int val = 0;

	for (bool cont = true; cont;) {
		int numargs = MAXWORDS;

		// collect all argument values
		loopi(MAXWORDS) {
			w[i] = "";

			if (i > numargs)
				continue;

			// parse and evaluate exps
			char *s = parseword(p);
			if (!s) {
				numargs = i;
				s = "";
			}

			// substitute variables
			if (*s == '$')
				s = lookup(s);
			w[i] = s;
		};

		p += strcspn(p, ";\n\0");

		// more statements if this isn't the end of the string
		cont = *p++ != 0;
		char *c = w[0];

		// strip irc-style command prefix
		if (*c == '/')
			c++;

		// empty statement
		if (!*c)
			continue;

		@autoreleasepool {
			Ident *i = idents[@(c)];;

			if (i == nil) {
				val = ATOI(c);

				if (!val && *c != '0')
					conoutf("unknown command: %s", c);
			} else {
				switch (i.type) {
				// game defined commands
				case ID_COMMAND:
					// use very ad-hoc function signature,
					// and just call it
					switch (i.narg) {
					case ARG_1INT:
						if (isdown)
							((void (__cdecl *)(int))i.fun)(ATOI(w[1]));
						break;
					case ARG_2INT:
						if (isdown)
							((void (__cdecl *)(int, int))i.fun)(ATOI(w[1]), ATOI(w[2]));
						break;
					case ARG_3INT:
						if (isdown)
							((void (__cdecl *)(int, int, int))i.fun)(ATOI(w[1]), ATOI(w[2]), ATOI(w[3]));
						break;
					case ARG_4INT:
						if (isdown)
							((void (__cdecl *)(int, int, int, int))i.fun)(ATOI(w[1]), ATOI(w[2]), ATOI(w[3]), ATOI(w[4]));
						break;
					case ARG_NONE:
						if (isdown)
							((void (__cdecl *)())i.fun)();
						break;
					case ARG_1STR:
						if (isdown)
							((void (__cdecl *)(char *))i.fun)(w[1]);
						break;
					case ARG_2STR:
						if (isdown)
							((void (__cdecl *)(char *, char *))i.fun)(w[1], w[2]);
						break;
					case ARG_3STR:
						if (isdown)
							((void (__cdecl *)(char *, char *, char*))i.fun)(w[1], w[2], w[3]);
						break;
					case ARG_5STR:
						if (isdown)
							((void (__cdecl *)(char *, char *, char*, char*, char*))i.fun)(w[1], w[2], w[3], w[4], w[5]);
						break;
					case ARG_DOWN:
						((void (__cdecl *)(bool))i.fun)(isdown);
						break;
					case ARG_DWN1:
						((void (__cdecl *)(bool, char *))i.fun)(isdown, w[1]);
						break;
					case ARG_1EXP:
						if (isdown)
							val = ((int (__cdecl *)(int))i.fun)(execute(w[1]));
						break;
					case ARG_2EXP:
						if (isdown)
							val = ((int (__cdecl *)(int, int))i.fun)(execute(w[1]), execute(w[2]));
						break;
					case ARG_1EST:
						if (isdown)
							val = ((int (__cdecl *)(char *))i.fun)(w[1]);
						break;
					case ARG_2EST:
						if (isdown)
							val = ((int (__cdecl *)(char *, char *))i.fun)(w[1], w[2]);
						break;
					case ARG_VARI:
						if (isdown) {
							// limit, remove
							string r;

							r[0] = 0;

							for (int i = 1; i < numargs; i++) {
								// make string-list out of all arguments
								strcat_s(r, w[i]);

								if (i == numargs - 1)
									break;

								strcat_s(r, " ");
							}
							((void (__cdecl *)(char *))i.fun)(r);
						}
						break;
					}
					break;
				// game defined variabled
				case ID_VAR:
					if (isdown) {
						if (!w[1][0])
							// var with no value just prints its current value
							conoutf("%s = %d", c, *i.storage);
						else {
							if (i.min > i.max)
								conoutf("variable is read-only");
							else {
								int i1 = ATOI(w[1]);

								if (i1 < i.min || i1 > i.max) {
									// clamp to valid range
									i1 = i1 < i.min ? i.min : i.max;
									conoutf("valid range for %s is %d..%d", c, i.min, i.max);
								}
								*i.storage = i1;
							}

							if (i.fun != NULL)
								// call trigger function if available
								((void (__cdecl *)())i.fun)();
						}
					}
					break;
				// alias, also used as functions and (global) variables
				case ID_ALIAS:
					for (int i = 1; i < numargs; i++) {
						// set any arguments as (global) arg values so functions can access them
						sprintf_sd(t)("arg%d", i);
						alias(t, w[i]);
					}

					char *action = newstring([i.action UTF8String]);   // create new string here because alias could rebind itself
					val = execute(action, isdown);
					gp()->deallocstr(action);

					break;
				}
			}
		}

		loopj(numargs)
		    gp()->deallocstr(w[j]);
	}

	return val;
}

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

bool
execfile(const char *cfgfile)
{
	string s;
	strcpy_s(s, cfgfile);

	char *buf;
	@autoreleasepool {
		buf = loadfile(@(path(s)), NULL);
	}

	if (!buf)
		return false;

	execute(buf);
	free(buf);

	return true;
}

void exec(char *cfgfile)
{
    if(!execfile(cfgfile)) conoutf("could not read \"%s\"", cfgfile);
};

void writecfg()
{
	@autoreleasepool {
		OFFile *f = [OFFile fileWithPath: @"config.cfg"
					    mode: @"w"];

		if (f == NULL)
			return;

		[f writeString:
		    @"// automatically written on exit, do not modify\n"
		    @"// delete this file to have defaults.cfg overwrite "
		    @"these settings\n"
		    @"// modify settings in game, or put settings in "
		    @"autoexec.cfg to override anything\n\n"];

		writeclientinfo(f);
		[f writeString: @"\n"];

		[idents enumerateKeysAndObjectsUsingBlock:
		    ^ (OFString *name, Ident *i, bool *stop) {
			    if (i.type == ID_VAR && i.persist)
				    [f writeFormat: @"%@ %d\n",
						    i.name, *i.storage];
		}];
		[f writeString: @"\n"];

		writebinds(f);
		[f writeString: @"\n"];

		[idents enumerateKeysAndObjectsUsingBlock:
		    ^ (OFString *name, Ident *i, bool *stop) {
			if (i.type == ID_ALIAS &&
			    ![name hasPrefix: @"nextmap_"])
				[f writeFormat: @"alias \"%@\" [%@]\n",
						i.name, i.action];
		}];
	}
}

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

int add(int a, int b)   { return a+b; };
int mul(int a, int b)   { return a*b; };
int sub(int a, int b)   { return a-b; };
int divi(int a, int b)  { return b ? a/b : 0; };
int mod(int a, int b)   { return b ? a%b : 0; };
int equal(int a, int b) { return (int)(a==b); };
int lt(int a, int b)    { return (int)(a<b); };
int gt(int a, int b)    { return (int)(a>b); };

int strcmpa(char *a, char *b) { return strcmp(a,b)==0; };

int rndn(int a)    { return a>0 ? rnd(a) : 0; };

int explastmillis() { return lastmillis; };

void
init_command()
{
	COMMAND(alias, ARG_2STR);
	COMMAND(writecfg, ARG_NONE);
	COMMANDN(loop, loopa, ARG_2STR);
	COMMANDN(while, whilea, ARG_2STR);
	COMMANDN(if, ifthen, ARG_3STR);
	COMMAND(onrelease, ARG_DWN1);
	COMMAND(exec, ARG_1STR);
	COMMAND(concat, ARG_VARI);
	COMMAND(concatword, ARG_VARI);
	COMMAND(at, ARG_2STR);
	COMMAND(listlen, ARG_1EST);
	COMMANDN(+, add, ARG_2EXP);
	COMMANDN(*, mul, ARG_2EXP);
	COMMANDN(-, sub, ARG_2EXP);
	COMMANDN(div, divi, ARG_2EXP);
	COMMAND(mod, ARG_2EXP);
	COMMANDN(=, equal, ARG_2EXP);
	COMMANDN(<, lt, ARG_2EXP);
	COMMANDN(>, gt, ARG_2EXP);
	COMMANDN(strcmp, strcmpa, ARG_2EST);
	COMMANDN(rnd, rndn, ARG_1EXP);
	COMMANDN(millis, explastmillis, ARG_1EXP);
}
