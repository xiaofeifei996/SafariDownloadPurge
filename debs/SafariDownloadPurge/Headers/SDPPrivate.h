#pragma once

#import <Foundation/Foundation.h>

// Private SafariServices classes backing Safari's Downloads UI.
// Only the members this tweak touches are declared.

@interface _SFDownload : NSObject
- (NSURL *)completedFileURL;
- (NSString *)fileDownloadPath;
- (NSString *)filename;
- (NSURL *)sourceURL;
- (long long)state;
- (BOOL)isIdle;
- (NSDate *)dateAdded;
- (BOOL)removeFromDisk;
- (void)removeDataAndPlaceholderFromDisk;
@end

@interface _SFDownloadManager : NSObject
+ (id)sharedManager;
- (NSArray *)downloads;
- (NSURL *)downloadsRootURL;
- (void)removeDownloads:(NSArray *)downloads;
- (void)removeDownloadsStartedAfterDate:(NSDate *)date;
- (void)reloadDownloadsSynchronously;
@end

// Resolves once SafariServices has been linked into the process.
FOUNDATION_EXPORT Class SDPClassNamed(const char *name);
