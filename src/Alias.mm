#import "cube.h"

#import "Alias.h"

@implementation Alias
@synthesize action = _action;

- (int)executeWithArguments: (char**)w
	      argumentCount: (int)numargs
		     isDown: (bool)isDown
{
	int val;

	for (int i = 1; i < numargs; i++) {
		// set any arguments as (global) arg values so functions can
		// access them
		OFString *arg = [OFString stringWithFormat: @"arg%d", i];
		alias(arg, @(w[i]));
	}

	// create new string here because alias could rebind itself
	char *action = newstring([_action UTF8String]);
	val = execute(action, isDown);
	gp()->deallocstr(action);

	return val;
}
@end
