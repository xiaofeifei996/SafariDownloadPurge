#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SDPQueue.h"
#import "SDPConfig.h"
#import "SDPDebug.h"

// A removal can fail when Safari lacks the sandbox extension for the Downloads
// container. Those paths are queued and retried in the same process later, so
// the tweak never needs to be injected into SpringBoard (which would force the
// package manager to report a respring on install).

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
        });
        [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                          object:nil
                                                           queue:nil
                                                      usingBlock:^(__unused NSNotification *note) {
            SDPDrainNow();
        }];
    }
}
