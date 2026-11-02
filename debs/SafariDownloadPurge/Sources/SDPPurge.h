#pragma once

#import <Foundation/Foundation.h>

// Outcome keys reported back to the caller so the UI can describe what really
// happened instead of always claiming a deletion.
FOUNDATION_EXPORT NSString *const SDPPurgeReportRemoved;
FOUNDATION_EXPORT NSString *const SDPPurgeReportLogOnly;
FOUNDATION_EXPORT NSString *const SDPPurgeReportKeptInstaller;
FOUNDATION_EXPORT NSString *const SDPPurgeReportDeferred;
FOUNDATION_EXPORT NSString *const SDPPurgeReportSkipped;

// Removes the on-disk file belonging to each download record.
@interface SDPPurge : NSObject

+ (NSArray<NSString *> *)sdp_purgeDownloads:(NSArray *)downloads reason:(NSString *)reason;

// Same as above, additionally filling `report` with what happened per category.
+ (NSArray<NSString *> *)sdp_purgeDownloads:(NSArray *)downloads
                                     reason:(NSString *)reason
                                     report:(NSDictionary **)report;

@end
