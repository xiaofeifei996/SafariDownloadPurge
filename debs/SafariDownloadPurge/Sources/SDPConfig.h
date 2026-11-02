#pragma once

#import <Foundation/Foundation.h>

@interface SDPConfig : NSObject

+ (BOOL)sdp_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
+ (void)sdp_setBool:(BOOL)value forKey:(NSString *)key;

@end
