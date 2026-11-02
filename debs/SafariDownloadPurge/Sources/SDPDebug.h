#pragma once

#import <Foundation/Foundation.h>

// Append-only trace of what the injected processes actually saw and did. The
// panel reads it back, so a failed switch can be diagnosed from the device
// without a debugger attached.
@interface SDPDebug : NSObject

+ (void)sdp_log:(NSString *)format, ... NS_FORMAT_FUNCTION(1, 2);
+ (NSString *)sdp_recentLogWithLimit:(NSUInteger)lines;
+ (void)sdp_clearLog;

@end
