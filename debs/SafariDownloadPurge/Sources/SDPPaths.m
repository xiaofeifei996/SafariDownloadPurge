#import "SDPPaths.h"

static NSString *const SDPPreferenceFile = @"com.axs.safaridownloadpurge.plist";
static NSString *const SDPRelative = @"Library/Preferences/com.axs.safaridownloadpurge.plist";

static NSArray<NSString *> *SDPContainerPaths(void);

// Data containers of the processes this tweak is injected into. A sandboxed app
// can be denied the shared domain and end up reading its own container copy, so
// the panel has to keep those copies in sync too.
static NSArray<NSString *> *SDPContainerPaths(void) {
    // Containers appear and disappear while the device runs, so the result is
    // memoised briefly instead of once per process.
    static NSArray<NSString *> *memo;
    static NSTimeInterval memoTime;
    static NSLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        lock = [[NSLock alloc] init];
    });

    [lock lock];
    NSArray<NSString *> *cached = nil;
    if (memo && [NSDate date].timeIntervalSince1970 - memoTime < 2.0) {
        cached = memo;
    }
    [lock unlock];
    if (cached) {
        return cached;
    }

    NSMutableArray<NSString *> *list = [NSMutableArray array];
    NSString *dataRoot = @"/var/mobile/Containers/Data/Application";
    NSFileManager *manager = [NSFileManager defaultManager];
    for (NSString *app in [manager contentsOfDirectoryAtPath:dataRoot error:NULL]) {
        NSString *container = [dataRoot stringByAppendingPathComponent:app];
        NSString *metadata = [container stringByAppendingPathComponent:
                              @".com.apple.mobile_container_manager.metadata.plist"];
        NSString *identifier = [NSDictionary dictionaryWithContentsOfFile:metadata][@"MCMMetadataIdentifier"];
        if (![identifier isKindOfClass:[NSString class]]) {
            continue;
        }
        if (![identifier isEqualToString:@"com.apple.mobilesafari"] &&
            ![identifier isEqualToString:@"com.apple.SafariViewService"]) {
            continue;
        }
        [list addObject:[container stringByAppendingPathComponent:SDPRelative]];
    }

    [lock lock];
    memo = list;
    memoTime = [NSDate date].timeIntervalSince1970;
    [lock unlock];
    return list;
}

NSString *SDPCanonicalPreferencePath(void) {
    return [@"/var/mobile/Library/Preferences/" stringByAppendingPathComponent:SDPPreferenceFile];
}

// Shared copies, including the RootHide per-boot root when present.
static NSArray<NSString *> *SDPSharedPreferencePaths(void) {
    NSMutableArray<NSString *> *files = [NSMutableArray array];
    NSString *relative = [@"var/mobile/Library/Preferences" stringByAppendingPathComponent:
                          SDPPreferenceFile];
    [files addObject:[@"/" stringByAppendingPathComponent:relative]];
    [files addObject:[@"/var/jb/" stringByAppendingPathComponent:relative]];

    NSArray<NSString *> *entries =
        [[NSFileManager defaultManager] contentsOfDirectoryAtPath:
            @"/var/mobile/Containers/Shared/AppGroup" error:NULL];
    for (NSString *entry in entries) {
        if (![entry hasPrefix:@".jbroot-"]) {
            continue;
        }
        [files addObject:[NSString pathWithComponents:@[
            @"/var/mobile/Containers/Shared/AppGroup", entry, relative
        ]]];
    }
    return files;
}

NSArray<NSString *> *SDPInjectedContainerPreferencePaths(void) {
    return SDPContainerPaths();
}

NSArray<NSString *> *SDPPreferenceReadPaths(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    [paths addObjectsFromArray:SDPContainerPaths()];
    [paths addObjectsFromArray:SDPSharedPreferencePaths()];
    return paths;
}

NSArray<NSString *> *SDPPreferenceWritePaths(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    [paths addObject:SDPCanonicalPreferencePath()];
    [paths addObjectsFromArray:SDPContainerPaths()];
    for (NSString *path in SDPSharedPreferencePaths()) {
        // Mirror only into roots that already carry a copy, so a jailbreak root
        // this device is not using does not sprout new files.
        if ([paths containsObject:path]) {
            continue;
        }
        if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
            [paths addObject:path];
        }
    }
    return paths;
}
