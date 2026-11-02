#pragma once

#import <Foundation/Foundation.h>

// Lightweight, non-blocking confirmation shown inside Safari after an action.
@interface SDPToast : NSObject

+ (void)sdp_showRemovedCount:(NSUInteger)count;
+ (void)sdp_showProtectedCount:(NSUInteger)count;

@end
