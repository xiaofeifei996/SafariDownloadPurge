#import "SDPConfig.h"

static NSString *const SDPDomainName = @"com.axs.safaridownloadpurge";

// Candidate on-disk stores. cfprefsd normally answers the query; the direct
// file read keeps the tweak working in processes that cannot reach the store.
static NSArray<NSString *> *SDPPreferencePaths(void) {
    static NSArray<NSString *> *paths;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSMutableArray *list = [NSMutableArray array];
        NSString *base = @"/var/mobile/Library/Preferences/com.axs.safaridownloadpurge.plist";
        [list addObject:base];
        [list addObject:[@"/var/jb" stringByAppendingString:base]];
        NSFileManager *manager = [NSFileManager defaultManager];
        NSArray *entries =
            [manager contentsOfDirectoryAtPath:@"/var/mobile/Containers/Shared/AppGroup"
                                       error:NULL];
        for (NSString *entry in entries) {
            if (![entry hasPrefix:@".jbroot-"]) {
                continue;
            }
            NSString *path = [NSString pathWithComponents:@[
                @"/var/mobile/Containers/Shared/AppGroup", entry,
                @"var/mobile/Library/Preferences/com.axs.safaridownloadpurge.plist"
            ]];
            [list addObject:path];
        }
        paths = list;
    });
    return paths;
}

static NSDictionary *SDPFileSnapshot(void) {
    for (NSString *path in SDPPreferencePaths()) {
        if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
            continue;
        }
        NSDictionary *values = [NSDictionary dictionaryWithContentsOfFile:path];
        if ([values isKindOfClass:[NSDictionary class]] && values.count > 0) {
            return values;
        }
    }
    return nil;
}

@implementation SDPConfig

+ (BOOL)sdp_boolForKey:(NSString *)key defaultValue:(BOOL)defaultValue {
    if (key.length == 0) {
        return defaultValue;
    }
    CFPropertyListRef value = CFPreferencesCopyAppValue((__bridge CFStringRef)key,
                                                       (__bridge CFStringRef)SDPDomainName);
    id object = value ? (__bridge_transfer id)value : nil;
    if (!object) {
        object = SDPFileSnapshot()[key];
    }
    if ([object isKindOfClass:[NSNumber class]]) {
        return [object boolValue];
    }
    if ([object isKindOfClass:[NSString class]]) {
        return [object boolValue];
    }
    return defaultValue;
}

+ (void)sdp_setBool:(BOOL)value forKey:(NSString *)key {
    if (key.length == 0) {
        return;
    }
    CFPreferencesSetAppValue((__bridge CFStringRef)key,
                             (__bridge CFPropertyListRef)(value ? @YES : @NO),
                             (__bridge CFStringRef)SDPDomainName);
    CFPreferencesAppSynchronize((__bridge CFStringRef)SDPDomainName);
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.axs.safaridownloadpurge.preferences-changed"),
                                         NULL, NULL, true);
}

@end
