#import "SDPPaths.h"

static NSString *const SDPPreferenceFile = @"com.axs.safaridownloadpurge.plist";
static NSString *const SDPRelative = @"Library/Preferences/com.axs.safaridownloadpurge.plist";

// A single flat file outside every sandbox. Both the Settings panel and the
// injected Safari process can reach it, so it is the one place that always
// agrees. Everything else is only a mirror kept for compatibility.
static NSString *const SDPSharedFlagDirectory = @"/var/mobile/Library/SafariDownloadPurge";

static NSString *SDPSharedFlagPath(void) {
    return [SDPSharedFlagDirectory stringByAppendingPathComponent:@"state.plist"];
}

static NSArray<NSString *> *SDPContainerPaths(void);

// Data containers of the processes this tweak is injected into. Enumerating
// them needs read access to the container root, which Settings does not always
// have, so this list is advisory: the shared flag file is what decides.
static NSArray<NSString *> *SDPContainerPaths(void) {
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

NSString *SDPDisabledMarkerPath(void) {
    return [SDPSharedFlagDirectory stringByAppendingPathComponent:@"disabled"];
}

BOOL SDPDisabledMarkerPresent(void) {
    return [[NSFileManager defaultManager] fileExistsAtPath:SDPDisabledMarkerPath()];
}

void SDPSetDisabledMarker(BOOL disabled) {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:SDPSharedFlagDirectory
       withIntermediateDirectories:YES attributes:nil error:NULL];
    if (disabled) {
        [@"disabled" writeToFile:SDPDisabledMarkerPath()
                     atomically:YES
                       encoding:NSUTF8StringEncoding
                          error:NULL];
    } else {
        [manager removeItemAtPath:SDPDisabledMarkerPath() error:NULL];
    }
}

NSString *SDPCanonicalPreferencePath(void) {
    return [@"/var/mobile/Library/Preferences/" stringByAppendingPathComponent:SDPPreferenceFile];
}

NSString *SDPSharedStatePath(void) {
    return SDPSharedFlagPath();
}

NSArray<NSString *> *SDPSharedStatePaths(void) {
    return @[
        SDPSharedFlagPath(),
        [@"/var/jb/var/mobile/Library/Preferences" stringByAppendingPathComponent:SDPPreferenceFile],
        SDPCanonicalPreferencePath(),
    ];
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
    // The flat shared file comes first: it is the only copy that is guaranteed
    // to be visible from inside Safari's sandbox and from Settings alike.
    [paths addObjectsFromArray:SDPSharedStatePaths()];
    [paths addObjectsFromArray:SDPContainerPaths()];
    [paths addObjectsFromArray:SDPSharedPreferencePaths()];
    return paths;
}

NSArray<NSString *> *SDPPreferenceWritePaths(void) {
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    [paths addObject:SDPSharedFlagPath()];
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
