#pragma once

#import <Foundation/Foundation.h>

// A download file can live behind a sandbox extension only Safari holds. When
// unlinking fails, the path is queued and retried inside Safari itself on the
// next activation; nothing is ever injected into another process.
@interface SDPQueue : NSObject

+ (void)sdp_enqueuePaths:(NSArray<NSString *> *)paths;
+ (NSArray<NSString *> *)sdp_takePendingPaths;
+ (NSUInteger)sdp_drainPendingPaths;
+ (void)sdp_discardPendingPaths;
+ (NSUInteger)sdp_pendingCount;

@end
