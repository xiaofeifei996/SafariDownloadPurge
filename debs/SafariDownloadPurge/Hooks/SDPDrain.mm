#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "SDPQueue.h"
#import "SDPConfig.h"

// Sandboxed Safari may be denied the unlink even though the jailbreak grants the
// record. Paths that fail there are queued and drained here, in SpringBoard.
// The switch is re-read at drain time: a queued path must not survive the user
// turning the tweak off.

static void SDPDrainNow(void) {
    [SDPConfig sdp_synchronize];
    if (![SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES]) {
        // Drop the backlog instead of holding deletions the user cancelled.
        if ([SDPQueue sdp_pendingCount] > 0) {
            [SDPQueue sdp_discardPendingPaths];
            NSLog(@"[SafariDownloadPurge] disabled, dropped pending queue");
        }
        return;
    }
    NSUInteger removed = [SDPQueue sdp_drainPendingPaths];
    if (removed > 0) {
        NSLog(@"[SafariDownloadPurge] drain removed %lu file(s)", (unsigned long)removed);
    }
}

static void SDPDrainNotificationCallback(CFNotificationCenterRef center,
                                        void *observer,
                                        CFStringRef name,
                                        const void *object,
                                        CFDictionaryRef userInfo) {
    SDPDrainNow();
}

__attribute__((constructor)) static void SDPDrainEntry(void) {
    @autoreleasepool {
        NSString *bundle = [NSBundle mainBundle].bundleIdentifier ?: @"";
        if (![bundle containsString:@"SpringBoard"]) {
            return;
        }
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SDPDrainNotificationCallback,
                                        CFSTR("com.axs.safaridownloadpurge.drain"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        NULL,
                                        SDPDrainNotificationCallback,
                                        CFSTR("com.axs.safaridownloadpurge.preferences-changed"),
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)),
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
