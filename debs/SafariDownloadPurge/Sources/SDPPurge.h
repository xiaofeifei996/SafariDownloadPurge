#pragma once

#import <Foundation/Foundation.h>

// Removes the on-disk file belonging to each download record.
// Returns the list of removed paths (empty when nothing was touched).
@interface SDPPurge : NSObject

+ (NSArray<NSString *> *)sdp_purgeDownloads:(NSArray *)downloads reason:(NSString *)reason;

@end
