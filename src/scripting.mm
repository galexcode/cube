// command.cpp: implements the parsing and execution of a tiny script language
// which is largely backwards compatible with the quake console language.

#include "cube.h"

#import "Alias.h"
#import "Command.h"
#import "Variable.h"

static void
itoa(char *s, int i)
{
	sprintf_s(s)("%d", i);
}

static char*
exchangestr(char *o, const char *n)
{
	gp()->deallocstr(o);
	return newstring(n);
}

static OFMutableDictionary *idents = nil;

void
alias(OFString *name, OFString *action)
{
	Alias *alias = idents[name];

	if (alias == nil) {
		alias = [Alias new];
		alias.name = name;
		alias.action = action;
		alias.persist = true;

		idents[name] = alias;
	} else {
		if ([alias isKindOfClass: [Alias class]])
			alias.action = action;
		else
			conoutf("cannot redefine builtin %s with an alias",
			    [name UTF8String]);
	}
}

// variable's and commands are registered through globals, see cube.h
int
variable(OFString *name, int min, int cur, int max, int *storage, void (*fun)(),
    bool persist)
{
	if (idents == nil)
		idents = [OFMutableDictionary new];

	Variable *v = [Variable new];
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
	return (idents[name] != nil);
}

char*
getalias(char *name)
{
	@autoreleasepool {
		Alias *alias = idents[@(name)];

		if ([alias isKindOfClass: [Alias class]])
			/* FIXME: Evil cast as a temporary workaround */
			return (char*)[alias.action UTF8String];
	}

	return NULL;
}

bool
addcommand(OFString *name, void (*fun)(), int narg)
{
	if (idents == nil)
		idents = [OFMutableDictionary new];

	Command *c = [Command new];
	c.name = name;
	c.fun = fun;
	c.narg = narg;

	idents[name] = c;

	return false;
}

// parse any nested set of () or []
static char*
parseexp(char *&p, int right)
{
	int left = *p++;
	char *word = p;

	for (int brak = 1; brak;) {
		int c = *p++;
		if (c == '\r')
			// hack
			*(p - 1) = ' ';
		if (c == left)
			brak++;
		else if (c == right)
			brak--;
		else if (!c) {
			p--;
			conoutf("missing \"%c\"", right);
			return NULL;
		}
	}

	char *s = newstring(word, p - word - 1);

	if (left == '(') {
		string t;
		// evaluate () exps directly, and substitute result
		itoa(t, execute(s));
		s = exchangestr(s, t);
	}

	return s;
}

// parse single argument, including expressions
static char*
parseword(char *&p)
{
	p += strspn(p, " \t\r");

	if (p[0] == '/' && p[1] == '/')
		p += strcspn(p, "\n\0");

	if (*p=='\"') {
		char *s, *word = ++p;

		p += strcspn(p, "\"\r\n\0");
		s = newstring(word, p-word);

		if (*p == '\"')
			p++;

		return s;
	}

	if (*p == '(')
		return parseexp(p, ')');
	if (*p == '[')
		return parseexp(p, ']');

	char *word = p;
	p += strcspn(p, "; \t\r\n\0");

	if (p - word == 0)
		return NULL;

	return newstring(word, p-word);
}

// find value of ident referenced with $ in exp
static char*
lookup(char *n)
{
	@autoreleasepool {
		id i = idents[@(n + 1)];

		if (i != nil) {
			if ([i isKindOfClass: [Variable class]]) {
				string t;
				itoa(t, *[i storage]);
				return exchangestr(n, t);
			} else if ([i isKindOfClass: [Alias class]])
				return exchangestr(n, [[i action] UTF8String]);
		}
	}

	conoutf("unknown alias lookup: %s", n + 1);

	return n;
}

// all evaluation happens here, recursively
int
execute(char *p, bool isdown)
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
		}

		p += strcspn(p, ";\n\0");

		// more statements if this isn't the end of the string
		cont = (*p++ != 0);
		char *c = w[0];

		// strip irc-style command prefix
		if (*c == '/')
			c++;

		// empty statement
		if (*c == 0)
			continue;

		@autoreleasepool {
			id i = idents[@(c)];

			if (i == nil) {
				val = ATOI(c);

				if (!val && *c != '0')
					conoutf("unknown command: %s", c);
			} else {
				// game defined command or alias (aliases are
				// also used as functions and (global)
				// variables)
				if ([i isKindOfClass: [Command class]] ||
				    [i isKindOfClass: [Alias class]])
					val = [i executeWithArguments: w
							argumentCount: numargs
							       isDown: isdown];
				// game defined variable
				else if ([i isKindOfClass: [Variable class]])
					[i assignWithName: c
						    value: w[1]
						   isDown: isdown];
			}
		}

		loopj(numargs)
		    gp()->deallocstr(w[j]);
	}

	return val;
}

// tab-completion of all idents

int completesize = 0, completeidx = 0;

void
resetcomplete()
{
	completesize = 0;
}

void
complete(char *s)
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
		    ^ (OFString *name, Variable *v, bool *stop) {
			    if ([v isKindOfClass: [Variable class]] &&
				v.persist)
				    [f writeFormat: @"%@ %d\n",
						    v.name, *v.storage];
		}];
		[f writeString: @"\n"];

		writebinds(f);
		[f writeString: @"\n"];

		[idents enumerateKeysAndObjectsUsingBlock:
		    ^ (OFString *name, Alias *a, bool *stop) {
			if ([a isKindOfClass: [Alias class]] &&
			    ![name hasPrefix: @"nextmap_"])
				[f writeFormat: @"alias \"%@\" [%@]\n",
						a.name, a.action];
		}];
	}
}

// below the commands that implement a small imperative language. thanks to the semantics of
// () and [] expressions, any control construct can be defined trivially.

void
intset(char *name, int v)
{
	@autoreleasepool {
		alias(@(name), [OFString stringWithFormat: @"%d", v]);
	}
}

void ifthen(char *cond, char *thenp, char *elsep) { execute(cond[0]!='0' ? thenp : elsep); };
void loopa(char *times, char *body) { int t = atoi(times); loopi(t) { intset("i", i); execute(body); }; };
void whilea(char *cond, char *body) { while(execute(cond)) execute(body); };    // can't get any simpler than this :)
void onrelease(bool on, char *body) { if(!on) execute(body); };

void
concat(char *s)
{
	@autoreleasepool {
		alias(@"s", @(s));
	}
}

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
	COMMAND(alias, ARG_2OSTR);
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
