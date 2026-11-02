#pragma once

#import <Foundation/Foundation.h>

// Configuration access shared by the tweak and the preference bundle.
// Reads are always live: the value that gates deletion must never come from a
// cache that could disagree with what the user just toggled.
@interface SDPConfig : NSObject

+ (BOOL)sdp_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;
+ (void)sdp_setBool:(BOOL)value forKey:(NSString *)key;

// Pulls a fresh snapshot from cfprefsd; called before any deletion decision so
// a long-lived process cannot act on its launch-time cache.
+ (void)sdp_synchronize;

// Human readable "store -> value" summary used by the panel's diagnostics row.
+ (NSString *)sdp_diagnostics;
+ (NSString *)sdp_storeSummary;

@end
