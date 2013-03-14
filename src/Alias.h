#import "Identifier.h"

@interface Alias: Identifier
{
	OFString *_action;
}

@property (copy) OFString *action;

- (int)executeWithArguments: (char**)arguments
	      argumentCount: (int)argumentCount
		     isDown: (bool)isDown;
@end
