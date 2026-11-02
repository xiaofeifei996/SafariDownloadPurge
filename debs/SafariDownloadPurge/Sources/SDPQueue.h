#pragma once

#import <Foundation/Foundation.h>

// A download file can live behind a sandbox extension that only Safari holds.
// When unlinking fails there, the path is queued and drained from SpringBoard,
// which runs with broader file access under a jailbreak.
@interface SDPQueue : NSObject

+ (void)sdp_enqueuePaths:(NSArray<NSString *> *)paths;
+ (NSArray<NSString *> *)sdp_takePendingPaths;
+ (NSUInteger)sdp_drainPendingPaths;

@end
