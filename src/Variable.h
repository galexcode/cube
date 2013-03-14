#import "Identifier.h"

@interface Variable: Identifier
{
	int _min, _max;
	int *_storage;
	void (*_fun)();
	int _narg;
}

@property int min, max;
@property void (*fun)();
@property int *storage;
@property int narg;

- (void)assignWithName: (char*)name
		 value: (char*)value
		isDown: (bool)isDown;
@end
