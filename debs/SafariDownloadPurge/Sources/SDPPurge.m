#import "SDPPurge.h"
#import "SDPConfig.h"
#import <objc/message.h>
#import "SDPPrivate.h"
#import "SDPQueue.h"
#import "SDPDebug.h"

NSString *const SDPPurgeReportRemoved = @"removed";
NSString *const SDPPurgeReportLogOnly = @"logOnly";
NSString *const SDPPurgeReportKeptInstaller = @"keptInstaller";
NSString *const SDPPurgeReportDeferred = @"deferred";
NSString *const SDPPurgeReportSkipped = @"skipped";

// Types a user tends to keep on disk: installers and archives. Purging them
// together with the Safari entry is usually a mistake, so they survive by
// default and only the history row disappears.
static NSSet<NSString *> *SDPInstallerExtensions(void) {
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"ipa", @"tipa", @"deb", @"dylib", @"mobileprovision",
                                    @"p12", @"cer", @"dmg", @"xcarchive", @"rar", @"7z"]];
    });
    return set;
}

static NSString *SDPCanonicalPath(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}

// Sending to a class looked up by name avoids a hard link dependency on the
// private framework symbol, which is absent at load time.
static _SFDownloadManager *SDPSharedManager(void) {
    Class cls = SDPClassNamed("_SFDownloadManager");
    if (!cls) {
        return nil;
    }
    typedef id (*SDPSharedIMP)(id, SEL);
    @try {
        return ((SDPSharedIMP)objc_msgSend)((id)cls, @selector(sharedManager));
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

// Raw location of the finished file for one download record.
static NSURL *SDPFileURLForDownload(_SFDownload *download) {
    if (!download) {
        return nil;
    }
    NSURL *url = nil;
    @try {
        if ([download respondsToSelector:@selector(completedFileURL)]) {
            url = [download completedFileURL];
        }
    } @catch (__unused NSException *exception) {
        url = nil;
    }
    if ((!url || ![url isKindOfClass:[NSURL class]] || !url.isFileURL)) {
        url = nil;
        @try {
            NSString *path = [download fileDownloadPath];
            if ([path isKindOfClass:[NSString class]] && path.length > 0) {
                url = [NSURL fileURLWithPath:path];
            }
        } @catch (__unused NSException *exception) {
            url = nil;
        }
    }
    if (![url isKindOfClass:[NSURL class]] || !url.isFileURL) {
        return nil;
    }
    return url;
}

// A record must never be allowed to point outside a Downloads folder.
static BOOL SDPPathLooksLikeDownload(NSString *path, NSString *rootPath) {
    if (path.length == 0) {
        return NO;
    }
    if (rootPath.length > 0) {
        if ([path isEqualToString:rootPath]) {
            return NO;
        }
        NSString *prefix = [rootPath hasSuffix:@"/"] ? rootPath
                                                     : [rootPath stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) {
            return YES;
        }
    }
    // Safari keeps downloads under its own data container on some builds, and
    // the manager's root is not always loaded yet when the removal arrives.
    for (NSString *marker in @[@"/Downloads/", @"/Downloads"]) {
        if ([path containsString:marker] && ![path hasSuffix:@"/Downloads"]) {
            return [path hasPrefix:@"/var/mobile/"] || [path hasPrefix:@"/private/var/mobile/"];
        }
    }
    return NO;
}

static NSString *SDPRootPath(_SFDownloadManager *manager) {
    if (!manager || ![manager respondsToSelector:@selector(downloadsRootURL)]) {
        return nil;
    }
    @try {
        NSURL *root = [manager downloadsRootURL];
        if ([root isKindOfClass:[NSURL class]]) {
            return SDPCanonicalPath(root.path);
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return nil;
}

// Paths of the records being removed, so they are excluded by value. Safari can
// hand over instances that are not identical to the ones in `downloads`; an
// identity check there made every file look "still referenced" and silently
// skipped the deletion.
static NSSet<NSString *> *SDPPathsOfRecords(NSArray *records) {
    NSMutableSet<NSString *> *paths = [NSMutableSet set];
    for (id record in records) {
        NSString *path = SDPCanonicalPath(SDPFileURLForDownload(record).path);
        if (path.length > 0) {
            [paths addObject:path];
        }
    }
    return paths;
}

// Files still owned by a surviving record must not be unlinked.
static NSSet<NSString *> *SDPPathsStillReferenced(_SFDownloadManager *manager,
                                                  NSArray *removing) {
    NSMutableSet<NSString *> *kept = [NSMutableSet set];
    if (!manager || ![manager respondsToSelector:@selector(downloads)]) {
        return kept;
    }
    NSArray *remaining = nil;
    @try {
        remaining = [manager downloads];
    } @catch (__unused NSException *exception) {
        remaining = nil;
    }
    if (![remaining isKindOfClass:[NSArray class]]) {
        return kept;
    }
    NSSet<NSString *> *removingPaths = SDPPathsOfRecords(removing);
    for (id record in remaining) {
        NSString *path = SDPCanonicalPath(SDPFileURLForDownload(record).path);
        if (path.length == 0) {
            continue;
        }
        if ([removingPaths containsObject:path] || [removing containsObject:record]) {
            continue;
        }
        [kept addObject:path];
    }
    return kept;
}

@implementation SDPPurge

+ (NSArray<NSString *> *)sdp_purgeDownloads:(NSArray *)downloads reason:(NSString *)reason {
    return [self sdp_purgeDownloads:downloads reason:reason report:NULL];
}

+ (NSArray<NSString *> *)sdp_purgeDownloads:(NSArray *)downloads
                                     reason:(NSString *)reason
                                     report:(NSDictionary **)report {
    NSMutableDictionary *outcome = [NSMutableDictionary dictionary];
    if (report) {
        *report = outcome;
    }
    if (![downloads isKindOfClass:[NSArray class]] || downloads.count == 0) {
        return @[];
    }

    // Gate on the live value at the moment of deletion: a stale snapshot here
    // makes the master switch look broken.
    [SDPConfig sdp_synchronize];
    if (![SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES]) {
        [SDPDebug sdp_log:@"未执行：总开关关闭"];
        return @[];
    }
    if ([reason isEqualToString:@"single"] &&
        ![SDPConfig sdp_boolForKey:@"purgeSingle" defaultValue:YES]) {
        [SDPDebug sdp_log:@"未执行：单个清除开关关闭"];
        return @[];
    }
    if ([reason isEqualToString:@"clear-all"] &&
        ![SDPConfig sdp_boolForKey:@"purgeClearAll" defaultValue:YES]) {
        [SDPDebug sdp_log:@"未执行：清除全部开关关闭"];
        return @[];
    }

    BOOL logOnly = [SDPConfig sdp_boolForKey:@"logOnly" defaultValue:NO];
    BOOL keepInstallers = [SDPConfig sdp_boolForKey:@"keepInstallers" defaultValue:NO];

    _SFDownloadManager *manager = SDPSharedManager();
    NSString *rootPath = SDPRootPath(manager);
    NSSet<NSString *> *referenced = SDPPathsStillReferenced(manager, downloads);

    NSFileManager *fm = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    NSMutableSet<NSString *> *handled = [NSMutableSet set];
    NSMutableArray<NSString *> *deferred = [NSMutableArray array];

    for (id record in downloads) {
        NSString *path = SDPCanonicalPath(SDPFileURLForDownload(record).path);
        if (path.length == 0 || [handled containsObject:path]) {
            continue;
        }
        [handled addObject:path];

        if (![fm fileExistsAtPath:path]) {
            [SDPDebug sdp_log:@"跳过（文件不存在）：%@", path];
            continue;
        }
        if (!SDPPathLooksLikeDownload(path, rootPath)) {
            [SDPDebug sdp_log:@"跳过（不在下载目录）：%@", path];
            outcome[SDPPurgeReportSkipped] = @([outcome[SDPPurgeReportSkipped] integerValue] + 1);
            continue;
        }
        if ([referenced containsObject:path]) {
            [SDPDebug sdp_log:@"跳过（仍被其它记录引用）：%@", path];
            continue;
        }
        NSString *extension = path.pathExtension.lowercaseString;
        if (keepInstallers && extension.length > 0 &&
            [SDPInstallerExtensions() containsObject:extension]) {
            [SDPDebug sdp_log:@"保留安装包/压缩包：%@", path];
            outcome[SDPPurgeReportKeptInstaller] =
                @([outcome[SDPPurgeReportKeptInstaller] integerValue] + 1);
            continue;
        }
        if (logOnly) {
            [SDPDebug sdp_log:@"只记录（未删除）：%@", path];
            outcome[SDPPurgeReportLogOnly] =
                @([outcome[SDPPurgeReportLogOnly] integerValue] + 1);
            continue;
        }

        NSError *error = nil;
        if ([fm removeItemAtPath:path error:&error]) {
            [SDPDebug sdp_log:@"已删除：%@", path];
            [removed addObject:path];
        } else {
            // Safari may lack the sandbox extension for the Downloads container;
            // retry later inside Safari instead of giving up.
            [SDPDebug sdp_log:@"删除失败转兜底 %@：%@", path, error.localizedDescription];
            [deferred addObject:path];
            [removed addObject:path];
            outcome[SDPPurgeReportDeferred] =
                @([outcome[SDPPurgeReportDeferred] integerValue] + 1);
        }
    }
    if (deferred.count > 0) {
        [SDPQueue sdp_enqueuePaths:deferred];
    }
    if (removed.count > 0) {
        outcome[SDPPurgeReportRemoved] = @(removed.count);
    }
    return removed;
}

@end
