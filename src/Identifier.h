#import <ObjFW/ObjFW.h>

@interface Identifier: OFObject
{
	OFString *_name;
	bool _persist;
}

@property (copy) OFString *name;
@property bool persist;
@end
