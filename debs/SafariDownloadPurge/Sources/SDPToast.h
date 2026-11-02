#pragma once

#import <Foundation/Foundation.h>

// Lightweight, non-blocking confirmation shown inside Safari after a purge.
@interface SDPToast : NSObject

+ (void)sdp_showRemovedCount:(NSUInteger)count;

@end
