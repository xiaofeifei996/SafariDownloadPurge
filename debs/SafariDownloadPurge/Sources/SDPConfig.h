#pragma once

#import <Foundation/Foundation.h>

// Configuration access shared by the tweak and the preference bundle.
// Reads are always live: the value that gates deletion must never come from a
// cache that could disagree with what the user just toggled.
@interface SDPConfig : NSObject

+ (BOOL)sdp_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue;

// Master switch read for destructive decisions. Returns NO whenever the stored
// value cannot be determined, so a broken preference store can never lead to a
// deletion the user did not ask for.
+ (BOOL)sdp_purgeEnabled;
+ (void)sdp_setBool:(BOOL)value forKey:(NSString *)key;

+ (NSString *)sdp_stringForKey:(NSString *)key;
+ (void)sdp_setString:(NSString *)value forKey:(NSString *)key;

// Pulls a fresh snapshot from cfprefsd; called before any deletion decision so
// a long-lived process cannot act on its launch-time cache.
+ (void)sdp_synchronize;

// 1.1.0 shipped keepInstallers=YES and the debug switch could be flipped by a
// plain "turn everything on" tap. Both make the tweak look broken, so an
// upgrade resets those two keys once, guarded by a schema marker.
+ (void)sdp_migrateIfNeeded;

// Human readable "store -> value" summary used by the panel's diagnostics row.
+ (NSString *)sdp_diagnostics;
+ (NSString *)sdp_storeSummary;

@end
