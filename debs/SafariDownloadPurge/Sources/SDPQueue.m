#import "SDPQueue.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const SDPQueueDomain = @"com.axs.safaridownloadpurge";
static NSString *const SDPQueueKey = @"pendingPurge";
static NSString *const SDPQueueNotification = @"com.axs.safaridownloadpurge.drain";

static NSArray<NSString *> *SDPQueueRead(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)SDPQueueKey,
                                                       (__bridge CFStringRef)SDPQueueDomain);
    NSArray *paths = nil;
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        paths = [(__bridge NSArray *)value copy];
    }
    if (value) {
        CFRelease(value);
    }
    return paths ?: @[];
}

static void SDPQueueWrite(NSArray<NSString *> *paths) {
    CFPreferencesSetAppValue((__bridge CFStringRef)SDPQueueKey,
                             (__bridge CFPropertyListRef)paths,
                             (__bridge CFStringRef)SDPQueueDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)SDPQueueDomain);
}

@implementation SDPQueue

+ (void)sdp_enqueuePaths:(NSArray<NSString *> *)paths {
    if (paths.count == 0) {
        return;
    }
    NSMutableArray *merged = [SDPQueueRead() mutableCopy];
    for (NSString *path in paths) {
        if (path.length > 0 && ![merged containsObject:path]) {
            [merged addObject:path];
        }
    }
    // Bound the queue so an unremovable file cannot grow it forever.
    while (merged.count > 200) {
        [merged removeObjectAtIndex:0];
    }
    SDPQueueWrite(merged);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         (__bridge CFStringRef)SDPQueueNotification,
                                         NULL, NULL, true);
}

+ (NSArray<NSString *> *)sdp_takePendingPaths {
    NSArray<NSString *> *paths = SDPQueueRead();
    if (paths.count > 0) {
        SDPQueueWrite(@[]);
    }
    return paths;
}

+ (NSUInteger)sdp_drainPendingPaths {
    NSArray<NSString *> *paths = [self sdp_takePendingPaths];
    if (paths.count == 0) {
        return 0;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *left = [NSMutableArray array];
    NSUInteger removed = 0;
    for (NSString *path in paths) {
        BOOL isDirectory = NO;
        if (![manager fileExistsAtPath:path isDirectory:&isDirectory]) {
            continue;
        }
        if (isDirectory) {
            [left addObject:path];
            continue;
        }
        NSError *error = nil;
        if ([manager removeItemAtPath:path error:&error]) {
            removed++;
            NSLog(@"[SafariDownloadPurge] drained: %@", path);
        } else {
            NSLog(@"[SafariDownloadPurge] drain failed %@: %@", path, error.localizedDescription);
            [left addObject:path];
        }
    }
    if (left.count > 0) {
        SDPQueueWrite(left);
    }
    return removed;
}

@end
