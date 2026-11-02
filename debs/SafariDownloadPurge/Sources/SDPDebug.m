#import "SDPDebug.h"

// The log lives in the tweak's own preferences domain so both Safari and the
// Settings panel can reach it without extra entitlements. Rotated by line count
// so it cannot grow without bound on a device that is never rebooted.

static NSString *const SDPDebugDomain = @"com.axs.safaridownloadpurge";
static NSString *const SDPDebugKey = @"debugLog";
static const NSUInteger SDPDebugMaxLines = 400;

static NSLock *SDPDebugLock(void) {
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
    });
    return lock;
}

static NSMutableArray<NSString *> *SDPDebugLoad(void) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)SDPDebugKey,
                                                       (__bridge CFStringRef)SDPDebugDomain);
    NSArray *array = nil;
    if (value && CFGetTypeID(value) == CFArrayGetTypeID()) {
        array = (__bridge_transfer NSArray *)value;
        value = NULL;
    }
    if (value) {
        CFRelease(value);
    }
    return [array isKindOfClass:[NSArray class]] ? [array mutableCopy]
                                                 : [NSMutableArray array];
}

static void SDPDebugStore(NSArray<NSString *> *lines) {
    CFPreferencesSetAppValue((__bridge CFStringRef)SDPDebugKey,
                             (__bridge CFPropertyListRef)lines,
                             (__bridge CFStringRef)SDPDebugDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)SDPDebugDomain);
}

@implementation SDPDebug

+ (void)sdp_log:(NSString *)format, ... {
    if (format.length == 0) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    if (!message) {
        return;
    }
    NSLog(@"[SafariDownloadPurge] %@", message);

    static NSDateFormatter *formatter;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"HH:mm:ss.SSS";
    });
    NSString *line = [NSString stringWithFormat:@"%@ [%@] %@",
                      [formatter stringFromDate:[NSDate date]],
                      [NSProcessInfo processInfo].processName ?: @"?",
                      message];

    [SDPDebugLock() lock];
    NSMutableArray<NSString *> *lines = SDPDebugLoad();
    [lines addObject:line];
    while (lines.count > SDPDebugMaxLines) {
        [lines removeObjectAtIndex:0];
    }
    SDPDebugStore(lines);
    [SDPDebugLock() unlock];
}

+ (NSString *)sdp_recentLogWithLimit:(NSUInteger)lines {
    [SDPDebugLock() lock];
    NSArray<NSString *> *all = SDPDebugLoad();
    [SDPDebugLock() unlock];
    NSUInteger count = MIN(lines, all.count);
    if (count == 0) {
        return @"(暂无日志)";
    }
    NSArray<NSString *> *tail = [all subarrayWithRange:NSMakeRange(all.count - count, count)];
    return [tail componentsJoinedByString:@"\n"];
}

+ (void)sdp_clearLog {
    [SDPDebugLock() lock];
    SDPDebugStore(@[]);
    [SDPDebugLock() unlock];
}

@end
