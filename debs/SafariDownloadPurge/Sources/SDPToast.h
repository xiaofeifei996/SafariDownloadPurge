#pragma once

#import <Foundation/Foundation.h>

// Lightweight, non-blocking confirmation shown inside Safari after an action.
@interface SDPToast : NSObject

+ (void)sdp_showRemovedCount:(NSUInteger)count;
+ (void)sdp_showProtectedCount:(NSUInteger)count;

// Describes what actually happened: "保留安装包 1 个", "只记录 2 个" ...
+ (void)sdp_showReport:(NSDictionary<NSString *, NSNumber *> *)report;

@end
