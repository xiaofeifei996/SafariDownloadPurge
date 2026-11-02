#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import "SDPPrivate.h"

// Private SafariServices classes are not present until the framework loads.
// objc_getClass only finds already-registered classes, while NSClassFromString
// forces the bundle lookup and registers the image.
Class SDPClassNamed(const char *name) {
    if (!name) {
        return Nil;
    }
    Class cls = objc_getClass(name);
    if (cls) {
        return cls;
    }
    NSString *string = [NSString stringWithUTF8String:name];
    if (string.length == 0) {
        return Nil;
    }
    return NSClassFromString(string);
}
