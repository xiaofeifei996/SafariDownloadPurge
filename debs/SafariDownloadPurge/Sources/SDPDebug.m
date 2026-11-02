#import "SDPDebug.h"
#import <CoreFoundation/CoreFoundation.h>

// The log has to cross sandboxes: it is written from inside Safari and read in
// Settings. Preferences are per-process containers there, so the log lives in
// the same flat file as the configuration instead.
//
// One line per process is appended, newest last, and the file is trimmed by
// line count so it cannot grow without bound.

static NSString *const SDPDebugLogPath = @"/var/mobile/Library/SafariDownloadPurge/debug.log";
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

static NSString *SDPDebugLogFile(void) {
    NSString *directory = [SDPDebugLogPath stringByDeletingLastPathComponent];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:NULL];
    return SDPDebugLogPath;
}

static NSMutableArray<NSString *> *SDPDebugLoad(void) {
    NSString *text = [NSString stringWithContentsOfFile:SDPDebugLogFile()
                                               encoding:NSUTF8StringEncoding
                                                  error:NULL];
    if (text.length == 0) {
        return [NSMutableArray array];
    }
    NSArray<NSString *> *lines = [text componentsSeparatedByString:@"\n"];
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *line in lines) {
        if (line.length > 0) {
            [kept addObject:line];
        }
    }
    return kept;
}

static void SDPDebugStore(NSArray<NSString *> *lines) {
    NSString *text = [lines componentsJoinedByString:@"\n"];
    [text writeToFile:SDPDebugLogFile() atomically:YES encoding:NSUTF8StringEncoding error:NULL];
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
    if (all.count == 0) {
        // Older builds kept the log in preferences; show it if nothing newer.
        CFPropertyListRef legacy = CFPreferencesCopyAppValue((__bridge CFStringRef)SDPDebugKey,
                                                            (__bridge CFStringRef)SDPDebugDomain);
        NSArray *old = legacy ? (__bridge_transfer NSArray *)legacy : nil;
        if ([old isKindOfClass:[NSArray class]] && old.count > 0) {
            return [old componentsJoinedByString:@"\n"];
        }
        return @"(暂无日志)";
    }
    NSUInteger count = MIN(lines, all.count);
    NSArray<NSString *> *tail = [all subarrayWithRange:NSMakeRange(all.count - count, count)];
    return [tail componentsJoinedByString:@"\n"];
}

+ (void)sdp_clearLog {
    [SDPDebugLock() lock];
    SDPDebugStore(@[]);
    CFPreferencesSetAppValue((__bridge CFStringRef)SDPDebugKey, (__bridge CFPropertyListRef)@[],
                             (__bridge CFStringRef)SDPDebugDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)SDPDebugDomain);
    [SDPDebugLock() unlock];
}

@end
