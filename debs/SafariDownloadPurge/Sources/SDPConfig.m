#import "SDPConfig.h"
#import "SDPPaths.h"
#import <CoreFoundation/CoreFoundation.h>

static NSString *const SDPDomainName = @"com.axs.safaridownloadpurge";
static NSString *const SDPRevisionKey = @"__sdpRevision";

static double SDPNumberAsDouble(id object) {
    return [object isKindOfClass:[NSNumber class]] ? [object doubleValue] : 0.0;
}

static BOOL SDPBoolFromObject(id object) {
    if ([object isKindOfClass:[NSNumber class]]) {
        return [object boolValue];
    }
    if ([object isKindOfClass:[NSString class]]) {
        NSString *text = [(NSString *)object lowercaseString];
        return [text isEqualToString:@"1"] || [text isEqualToString:@"yes"] ||
               [text isEqualToString:@"true"] || [text isEqualToString:@"on"];
    }
    return NO;
}

static id SDPCfPreferenceValue(NSString *key) {
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                         (__bridge CFStringRef)SDPDomainName);
    return value ? (__bridge_transfer id)value : nil;
}

// The copy carrying `key` with the highest revision stamp. Older builds wrote
// no stamp, so file modification time stands in for one.
static NSDictionary *SDPBestFileSnapshot(NSString *key, NSString **originPath) {
    NSDictionary *best = nil;
    double bestRevision = -1;
    NSString *bestPath = nil;

    for (NSString *path in SDPPreferenceReadPaths()) {
        NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![values isKindOfClass:[NSDictionary class]] || !values[key]) {
            continue;
        }
        double revision = SDPNumberAsDouble(values[SDPRevisionKey]);
        if (revision <= 0) {
            NSDictionary *attributes =
                [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
            NSDate *date = attributes[NSFileModificationDate];
            revision = date ? [date timeIntervalSince1970] : 0;
        }
        if (!best || revision > bestRevision) {
            best = values;
            bestRevision = revision;
            bestPath = path;
        }
    }
    if (originPath) {
        *originPath = bestPath;
    }
    return best;
}

@implementation SDPConfig

+ (void)sdp_synchronize {
    // Makes the daemon hand over writes made by other processes before the next
    // read, so a long-lived app cannot answer from its launch-time snapshot.
    CFPreferencesAppSynchronize((__bridge CFStringRef)SDPDomainName);
}

+ (BOOL)sdp_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    if (key.length == 0) {
        return defaultValue;
    }
    id cached = SDPCfPreferenceValue(key);
    double cachedRevision = SDPNumberAsDouble(SDPCfPreferenceValue(SDPRevisionKey));
    NSDictionary *snapshot = SDPBestFileSnapshot(key, NULL);
    id fileValue = snapshot[key];
    double fileRevision = SDPNumberAsDouble(snapshot[SDPRevisionKey]);

    // A sandboxed process can answer from its own container, while the panel
    // wrote elsewhere. The revision stamp written with every change decides
    // which copy is authoritative; on a tie the daemon answer wins.
    if (fileValue && fileRevision > cachedRevision) {
        return SDPBoolFromObject(fileValue);
    }
    if (cached) {
        return SDPBoolFromObject(cached);
    }
    if (fileValue) {
        return SDPBoolFromObject(fileValue);
    }
    return defaultValue;
}

+ (void)sdp_setBool:(BOOL)value forKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    NSNumber *number = value ? @YES : @NO;
    NSNumber *revision = @([[NSDate date] timeIntervalSince1970]);

    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)number,
                             (__bridge CFStringRef)SDPDomainName);
    CFPreferencesSetAppValue((__bridge CFStringRef)SDPRevisionKey,
                             (__bridge CFPropertyListRef)revision,
                             (__bridge CFStringRef)SDPDomainName);
    CFPreferencesAppSynchronize((__bridge CFStringRef)SDPDomainName);

    // Every copy must agree. A single stale copy used to win depending on which
    // process read it, which made the master switch look dead.
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *path in SDPPreferenceWritePaths()) {
        NSMutableDictionary *values = nil;
        NSDictionary *existing = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([existing isKindOfClass:[NSDictionary class]]) {
            values = [existing mutableCopy];
        }
        if (!values) {
            values = [NSMutableDictionary dictionary];
        }
        values[key] = number;
        values[SDPRevisionKey] = revision;
        [manager createDirectoryAtPath:[path stringByDeletingLastPathComponent]
           withIntermediateDirectories:YES attributes:nil error:NULL];
        [values writeToFile:path atomically:YES];
    }

    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.axs.safaridownloadpurge.preferences-changed"),
                                         NULL, NULL, true);
}

+ (NSString *)sdp_storeSummary {
    NSMutableArray<NSString *> *lines = [NSMutableArray array];
    id cached = SDPCfPreferenceValue(@"enabled");
    id cachedRevision = SDPCfPreferenceValue(SDPRevisionKey);
    [lines addObject:[NSString stringWithFormat:@"cfprefsd = %@（rev %@）",
                      cached ? [cached description] : @"(none)",
                      cachedRevision ? [cachedRevision description] : @"0"]];

    for (NSString *path in SDPPreferenceReadPaths()) {
        NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path];
        if (![values isKindOfClass:[NSDictionary class]]) {
            continue;
        }
        NSString *value = values[@"enabled"] ? [values[@"enabled"] description] : @"(none)";
        NSString *revision = values[SDPRevisionKey] ? [values[SDPRevisionKey] description] : @"0";
        [lines addObject:[NSString stringWithFormat:@"%@ = %@（rev %@）", path, value, revision]];
    }
    return [lines componentsJoinedByString:@"\n"];
}

+ (NSString *)sdp_diagnostics {
    BOOL enabled = [self sdp_boolForKey:@"enabled" defaultValue:YES];
    return [NSString stringWithFormat:@"当前生效：enabled = %@\n\n%@",
            enabled ? @"YES（会删除文件）" : @"NO（只清记录）",
            [self sdp_storeSummary]];
}

@end
