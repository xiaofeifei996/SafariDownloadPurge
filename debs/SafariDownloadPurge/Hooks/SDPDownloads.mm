#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "SDPPrivate.h"
#import "SDPPurge.h"
#import "SDPProtect.h"
#import "SDPToast.h"
#import "SDPConfig.h"
#import "SDPDebug.h"

// Safari removes download rows through _SFDownloadManager, and it may unlink the
// file in the same pass. Two behaviours hang off that single call:
//   enabled  -> delete the file ourselves, before the record goes
//   disabled -> park the file behind a hard link and put it back afterwards

static void (*SDPOrigRemoveDownloads)(id, SEL, NSArray *);
static void (*SDPOrigRemoveAfterDate)(id, SEL, NSDate *);
static BOOL (*SDPOrigRemoveFromDisk)(id, SEL);
static void (*SDPOrigRemoveDataFromDisk)(id, SEL);
static BOOL SDPInstalled = NO;

static NSURL *SDPFileURLOf(id record) {
    if (!record) {
        return nil;
    }
    @try {
        if ([record respondsToSelector:@selector(completedFileURL)]) {
            id value = ((id (*)(id, SEL))objc_msgSend)(record, @selector(completedFileURL));
            if ([value isKindOfClass:[NSURL class]] && ((NSURL *)value).isFileURL) {
                return value;
            }
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return nil;
}

static NSArray<NSString *> *SDPPathsOf(NSArray *records) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (id record in records) {
        NSString *path = SDPFileURLOf(record).path;
        if (path.length > 0) {
            [paths addObject:path];
        }
    }
    return paths;
}

static id SDPSharedManager(void) {
    Class cls = SDPClassNamed("_SFDownloadManager");
    if (!cls) {
        return nil;
    }
    @try {
        return ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedManager));
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSArray *SDPAllDownloads(void) {
    id manager = SDPSharedManager();
    if (!manager || ![manager respondsToSelector:@selector(downloads)]) {
        return nil;
    }
    @try {
        id all = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(downloads));
        return [all isKindOfClass:[NSArray class]] ? all : nil;
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

static NSString *SDPReasonFor(NSArray *removing) {
    NSArray *all = SDPAllDownloads();
    if (removing.count > 1 && all && removing.count >= all.count) {
        return @"clear-all";
    }
    return removing.count > 1 ? @"multi" : @"single";
}

static void SDPHandleRemoval(NSArray *removing, NSString *reason) {
    [SDPConfig sdp_synchronize];
    BOOL enabled = [SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES];
    NSArray<NSString *> *paths = SDPPathsOf(removing);
    [SDPDebug sdp_log:@"remove reason=%@ count=%lu enabled=%@ paths=%@",
     reason, (unsigned long)removing.count, enabled ? @"YES" : @"NO", paths];

    if (enabled) {
        NSArray<NSString *> *removed = [SDPPurge sdp_purgeDownloads:removing reason:reason];
        [SDPDebug sdp_log:@"删除结果：%lu 个", (unsigned long)removed.count];
        if (removed.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [SDPToast sdp_showRemovedCount:removed.count];
            });
        }
    } else {
        // Protection: keep the bytes alive across Safari's own deletion.
        NSUInteger parked = [SDPProtect sdp_stashPaths:paths];
        [SDPDebug sdp_log:@"保护模式：暂存 %lu 个文件", (unsigned long)parked];
    }
}

// Restores after the original method has run, when Safari may have unlinked.
static void SDPFinishRemoval(NSArray *removing) {
    [SDPConfig sdp_synchronize];
    if ([SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES]) {
        return;
    }
    NSArray<NSString *> *paths = SDPPathsOf(removing);
    if (paths.count == 0) {
        return;
    }
    NSUInteger restored = [SDPProtect sdp_restorePaths:paths];
    [SDPDebug sdp_log:@"保护模式：还原 %lu 个文件", (unsigned long)restored];
    if (restored > 0) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [SDPToast sdp_showProtectedCount:restored];
        });
    }
}

static void SDPRemoveDownloads(id self, SEL _cmd, NSArray *downloads) {
    if ([downloads isKindOfClass:[NSArray class]] && downloads.count > 0) {
        SDPHandleRemoval(downloads, SDPReasonFor(downloads));
    }
    if (SDPOrigRemoveDownloads) {
        SDPOrigRemoveDownloads(self, _cmd, downloads);
    }
    if ([downloads isKindOfClass:[NSArray class]] && downloads.count > 0) {
        SDPFinishRemoval(downloads);
    }
}

static void SDPRemoveDownloadsAfterDate(id self, SEL _cmd, NSDate *date) {
    NSMutableArray *victims = [NSMutableArray array];
    for (id record in SDPAllDownloads()) {
        id added = nil;
        @try {
            if ([record respondsToSelector:@selector(dateAdded)]) {
                added = ((id (*)(id, SEL))objc_msgSend)(record, @selector(dateAdded));
            }
        } @catch (__unused NSException *exception) {
            added = nil;
        }
        BOOL matches = !date;
        if (!matches && [added isKindOfClass:[NSDate class]]) {
            matches = [added compare:date] != NSOrderedAscending;
        }
        if (matches) {
            [victims addObject:record];
        }
    }
    if (victims.count > 0) {
        SDPHandleRemoval(victims, @"clear-all");
    }
    if (SDPOrigRemoveAfterDate) {
        SDPOrigRemoveAfterDate(self, _cmd, date);
    }
    if (victims.count > 0) {
        SDPFinishRemoval(victims);
    }
}

// Single-record deletion on newer builds; the file is unlinked here directly.
static BOOL SDPRemoveFromDisk(id self, SEL _cmd) {
    [SDPConfig sdp_synchronize];
    BOOL enabled = [SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES];
    NSArray<NSString *> *paths = SDPPathsOf(@[self]);
    [SDPDebug sdp_log:@"removeFromDisk enabled=%@ paths=%@", enabled ? @"YES" : @"NO", paths];
    if (enabled) {
        [SDPPurge sdp_purgeDownloads:@[self] reason:@"single"];
    } else {
        [SDPProtect sdp_stashPaths:paths];
    }
    BOOL result = SDPOrigRemoveFromDisk ? SDPOrigRemoveFromDisk(self, _cmd) : NO;
    if (!enabled) {
        [SDPProtect sdp_restorePaths:paths];
    }
    return result;
}

static void SDPRemoveDataFromDisk(id self, SEL _cmd) {
    [SDPConfig sdp_synchronize];
    BOOL enabled = [SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES];
    NSArray<NSString *> *paths = SDPPathsOf(@[self]);
    [SDPDebug sdp_log:@"removeDataAndPlaceholder enabled=%@ paths=%@",
     enabled ? @"YES" : @"NO", paths];
    if (enabled) {
        [SDPPurge sdp_purgeDownloads:@[self] reason:@"single"];
    } else {
        [SDPProtect sdp_stashPaths:paths];
    }
    if (SDPOrigRemoveDataFromDisk) {
        SDPOrigRemoveDataFromDisk(self, _cmd);
    }
    if (!enabled) {
        [SDPProtect sdp_restorePaths:paths];
    }
}

static BOOL SDPHookMethod(Class cls, SEL selector, IMP replacement, IMP *original) {
    if (!cls || !selector || class_getInstanceMethod(cls, selector) == NULL) {
        return NO;
    }
    MSHookMessageEx(cls, selector, replacement, original);
    return YES;
}

static void SDPInstallHooks(void) {
    if (SDPInstalled) {
        return;
    }
    Class manager = SDPClassNamed("_SFDownloadManager");
    if (!manager) {
        return;
    }
    BOOL hooked = NO;
    hooked |= SDPHookMethod(manager, @selector(removeDownloads:),
                            (IMP)SDPRemoveDownloads, (IMP *)&SDPOrigRemoveDownloads);
    hooked |= SDPHookMethod(manager, @selector(removeDownloadsStartedAfterDate:),
                            (IMP)SDPRemoveDownloadsAfterDate, (IMP *)&SDPOrigRemoveAfterDate);
    Class download = SDPClassNamed("_SFDownload");
    if (download) {
        hooked |= SDPHookMethod(download, @selector(removeFromDisk),
                                (IMP)SDPRemoveFromDisk, (IMP *)&SDPOrigRemoveFromDisk);
        hooked |= SDPHookMethod(download, @selector(removeDataAndPlaceholderFromDisk),
                                (IMP)SDPRemoveDataFromDisk,
                                (IMP *)&SDPOrigRemoveDataFromDisk);
    }
    if (hooked) {
        SDPInstalled = YES;
        [SDPDebug sdp_log:@"Hook 已安装（%@）", [NSProcessInfo processInfo].processName];
    }
}

// SafariServices can load after the tweak, so retry briefly at launch.
static void SDPScheduleInstall(NSUInteger attempt) {
    SDPInstallHooks();
    if (SDPInstalled || attempt >= 20) {
        if (!SDPInstalled) {
            [SDPDebug sdp_log:@"SafariServices 未出现，未安装 Hook"];
        }
        return;
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        SDPScheduleInstall(attempt + 1);
    });
}

__attribute__((constructor)) static void SDPEntry(void) {
    @autoreleasepool {
        NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"";
        if ([bundle containsString:@"SpringBoard"]) {
            return;
        }
        [SDPDebug sdp_log:@"插件载入 %@", [NSProcessInfo processInfo].processName];
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
            SDPInstallHooks();
        }];
        SDPScheduleInstall(0);
    }
}
