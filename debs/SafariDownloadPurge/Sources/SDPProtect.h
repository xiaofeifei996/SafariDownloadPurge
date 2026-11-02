#pragma once

#import <Foundation/Foundation.h>

// Safari may unlink a downloaded file on its own when the list entry is
// removed. With the tweak switched off the file must not disappear, so the
// paths are protected: a hard link is parked next to the original, and if the
// original is gone after the removal completes, the link is moved back.
@interface SDPProtect : NSObject

+ (NSUInteger)sdp_stashPaths:(NSArray<NSString *> *)paths;
+ (NSUInteger)sdp_restorePaths:(NSArray<NSString *> *)paths;
+ (NSUInteger)sdp_restoreAllStashesUnderRoot:(NSString *)rootPath;

@end
