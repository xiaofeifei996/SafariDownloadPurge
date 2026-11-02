#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <objc/message.h>
#import "SDPPrivate.h"
#import "SDPQueue.h"
#import "SDPConfig.h"
#import "SDPDebug.h"
#import "SDPProtect.h"

// A removal can fail when Safari lacks the sandbox extension for the Downloads
// container. Those paths are queued and retried in this same process, so the
// tweak never needs to touch another process.

// Removals that bypass _SFDownloadManager (list rows, QuickLook, the file
// presenter) are covered by the guard, but a POSIX unlink would slip past it.
// The parked hard link is the last line: put the file back if it disappeared
// while the tweak is switched off.
// Pre-parks every existing download file while the tweak is off, so a deletion
// that never reaches our hooks still leaves the bytes recoverable.
static void SDPPreParkAllDownloads(void) {
    Class cls = SDPClassNamed("_SFDownloadManager");
    if (!cls) {
        return;
    }
    NSArray *downloads = nil;
    @try {
        id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedManager));
        downloads = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(downloads));
    } @catch (__unused NSException *exception) {
        downloads = nil;
    }
    if (![downloads isKindOfClass:[NSArray class]]) {
        return;
    }
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (id record in downloads) {
        @try {
            id url = ((id (*)(id, SEL))objc_msgSend)(record, @selector(completedFileURL));
            if ([url isKindOfClass:[NSURL class]] && ((NSURL *)url).isFileURL) {
                [paths addObject:((NSURL *)url).path];
            }
        } @catch (__unused NSException *exception) {
            continue;
        }
    }
    if (paths.count > 0) {
        NSUInteger parked = [SDPProtect sdp_stashPaths:paths];
        [SDPDebug sdp_log:@"预保护 %lu/%lu 个下载文件",
         (unsigned long)parked, (unsigned long)paths.count];
    }
}

static void SDPRestoreProtectedFiles(void) {
    [SDPConfig sdp_synchronize];
    if ([SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES]) {
        return;
    }
    NSString *root = nil;
    Class cls = SDPClassNamed("_SFDownloadManager");
    if (cls) {
        @try {
            id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedManager));
            NSURL *url = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(downloadsRootURL));
            if ([url isKindOfClass:[NSURL class]]) {
                root = url.path;
            }
        } @catch (__unused NSException *exception) {
            root = nil;
        }
    }
    if (root.length == 0) {
        return;
    }
    NSUInteger restored = [SDPProtect sdp_restoreAllStashesUnderRoot:root];
    if (restored > 0) {
        [SDPDebug sdp_log:@"巡检：已还原 %lu 个被删除的文件", (unsigned long)restored];
        dispatch_async(dispatch_get_main_queue(), ^{
            [SDPToast sdp_showProtectedCount:restored];
        });
    }
}

static void SDPDrainNow(void) {
    [SDPConfig sdp_synchronize];
    if (![SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES]) {
        // Drop the backlog instead of holding deletions the user cancelled.
        if ([SDPQueue sdp_pendingCount] > 0) {
            [SDPQueue sdp_discardPendingPaths];
            [SDPDebug sdp_log:@"插件已关闭，清空待清理队列"];
        }
        return;
    }
    NSUInteger removed = [SDPQueue sdp_drainPendingPaths];
    if (removed > 0) {
        [SDPDebug sdp_log:@"兜底队列已清理 %lu 个文件", (unsigned long)removed];
    }
}

__attribute__((constructor)) static void SDPDrainEntry(void) {
    @autoreleasepool {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2 * NSEC_PER_SEC)),
                       dispatch_get_main_queue(), ^{
            SDPDrainNow();
            SDPPreParkAllDownloads();
            SDPRestoreProtectedFiles();
        });
        // A repeating check covers deletions that happen while Safari stays in
        // the foreground, where no activation notification follows.
        NSTimer *timer = [NSTimer scheduledTimerWithTimeInterval:5.0
                                                         repeats:YES
                                                           block:^(__unused NSTimer *t) {
            SDPPreParkAllDownloads();
            SDPRestoreProtectedFiles();
        }];
        (void)timer;
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
            SDPDrainNow();
            SDPRestoreProtectedFiles();
        }];
    }
}
