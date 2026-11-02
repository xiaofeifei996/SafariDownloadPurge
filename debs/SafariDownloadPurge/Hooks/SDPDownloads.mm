#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <substrate.h>
#import "SDPPrivate.h"
#import "SDPPurge.h"
#import "SDPToast.h"
#import "SDPConfig.h"

// Safari deletes download rows through _SFDownloadManager, but the downloaded
// file lives in the Downloads container and survives that deletion. Every
// history removal therefore unlinks the matching file first.

static void (*SDPOrigRemoveDownloads)(id, SEL, NSArray *);
static void (*SDPOrigRemoveAfterDate)(id, SEL, NSDate *);
static BOOL SDPInstalled = NO;

static NSArray *SDPAllDownloads(void) {
    _SFDownloadManager *manager = nil;
    @try {
        manager = (id)[SDPClassNamed("_SFDownloadManager") sharedManager];
    } @catch (__unused NSException *exception) {
        manager = nil;
    }
    if (!manager || ![manager respondsToSelector:@selector(downloads)]) {
        return nil;
    }
    NSArray *all = nil;
    @try {
        all = [manager downloads];
    } @catch (__unused NSException *exception) {
        all = nil;
    }
    return [all isKindOfClass:[NSArray class]] ? all : nil;
}

static void SDPPurgeAndReport(NSArray *removing, NSString *reason) {
    NSArray<NSString *> *removed = [SDPPurge sdp_purgeDownloads:removing reason:reason];
    if (removed.count == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        [SDPToast sdp_showRemovedCount:removed.count];
    });
}

static void SDPRemoveDownloads(id self, SEL _cmd, NSArray *downloads) {
    if ([downloads isKindOfClass:[NSArray class]] && downloads.count > 0) {
        NSArray *all = SDPAllDownloads();
        NSString *reason = @"single";
        if (downloads.count > 1) {
            reason = (all && downloads.count >= all.count) ? @"clear-all" : @"multi";
        }
        SDPPurgeAndReport(downloads, reason);
    }
    if (SDPOrigRemoveDownloads) {
        SDPOrigRemoveDownloads(self, _cmd, downloads);
    }
}

static void SDPRemoveDownloadsAfterDate(id self, SEL _cmd, NSDate *date) {
    NSMutableArray *victims = [NSMutableArray array];
    for (id record in SDPAllDownloads()) {
        id added = nil;
        @try {
            if ([record respondsToSelector:@selector(dateAdded)]) {
                added = [record performSelector:@selector(dateAdded)];
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
        SDPPurgeAndReport(victims, @"clear-all");
    }
    if (SDPOrigRemoveAfterDate) {
        SDPOrigRemoveAfterDate(self, _cmd, date);
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
    if (hooked) {
        SDPInstalled = YES;
        NSLog(@"[SafariDownloadPurge] hooks installed");
    }
}

// SafariServices can load after the tweak, so retry briefly at launch.
static void SDPScheduleInstall(NSUInteger attempt) {
    SDPInstallHooks();
    if (SDPInstalled || attempt >= 20) {
        if (!SDPInstalled) {
            NSLog(@"[SafariDownloadPurge] download manager never appeared");
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
        [[NSNotificationCenter defaultCenter] addObserverForName:NSBundleDidLoadNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
            SDPInstallHooks();
        }];
        SDPScheduleInstall(0);
    }
}
