#pragma once

#import <Foundation/Foundation.h>

// A download file can live behind a sandbox extension only Safari holds. When
// unlinking fails there, the path is queued and drained from SpringBoard, which
// has broader file access under a jailbreak.
@interface SDPQueue : NSObject

+ (void)sdp_enqueuePaths:(NSArray<NSString *> *)paths;
+ (NSArray<NSString *> *)sdp_takePendingPaths;
+ (NSUInteger)sdp_drainPendingPaths;
+ (void)sdp_discardPendingPaths;
+ (NSUInteger)sdp_pendingCount;

@end
