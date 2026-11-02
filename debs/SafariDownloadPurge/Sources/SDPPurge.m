#import "SDPPurge.h"
#import "SDPConfig.h"
#import <objc/message.h>
#import "SDPPrivate.h"
#import "SDPQueue.h"

// Types a user tends to keep on disk: installers and archives. Purging them
// together with the Safari entry is usually a mistake, so they survive by
// default and only the history row disappears.
static NSSet<NSString *> *SDPInstallerExtensions(void) {
    static NSSet<NSString *> *set;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        set = [NSSet setWithArray:@[@"ipa", @"tipa", @"deb", @"dylib", @"mobileprovision",
                                    @"p12", @"cer", @"dmg", @"xcarchive", @"rar", @"7z"]];
    });
    return set;
}

static NSString *SDPCanonicalPath(NSString *path) {
    if (path.length == 0) {
        return nil;
    }
    return [[path stringByStandardizingPath] stringByResolvingSymlinksInPath];
}

// Sending to a class looked up by name avoids a hard link dependency on the
// private framework symbol, which is absent at load time.
static _SFDownloadManager *SDPSharedManager(void) {
    Class cls = SDPClassNamed("_SFDownloadManager");
    if (!cls) {
        return nil;
    }
    typedef id (*SDPSharedIMP)(id, SEL);
    @try {
        return ((SDPSharedIMP)objc_msgSend)((id)cls, @selector(sharedManager));
    } @catch (__unused NSException *exception) {
        return nil;
    }
}

// Raw location of the finished file for one download record.
static NSURL *SDPFileURLForDownload(_SFDownload *download) {
    if (!download) {
        return nil;
    }
    NSURL *url = nil;
    @try {
        if ([download respondsToSelector:@selector(completedFileURL)]) {
            url = [download completedFileURL];
        }
    } @catch (__unused NSException *exception) {
        url = nil;
    }
    if ((!url || ![url isKindOfClass:[NSURL class]] || !url.isFileURL)) {
        url = nil;
        @try {
            NSString *path = [download fileDownloadPath];
            if ([path isKindOfClass:[NSString class]] && path.length > 0) {
                url = [NSURL fileURLWithPath:path];
            }
        } @catch (__unused NSException *exception) {
            url = nil;
        }
    }
    if (![url isKindOfClass:[NSURL class]] || !url.isFileURL) {
        return nil;
    }
    return url;
}

// A record must never be allowed to point outside a Downloads folder.
static BOOL SDPPathLooksLikeDownload(NSString *path, NSString *rootPath) {
    if (path.length == 0) {
        return NO;
    }
    if (rootPath.length > 0) {
        if ([path isEqualToString:rootPath]) {
            return NO;
        }
        NSString *prefix = [rootPath hasSuffix:@"/"] ? rootPath
                                                     : [rootPath stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) {
            return YES;
        }
    }
    // Fallback while the manager is still loading its history.
    if ([path hasSuffix:@"/Downloads"] || ![path containsString:@"/Downloads/"]) {
        return NO;
    }
    return [path hasPrefix:@"/var/mobile/"] || [path hasPrefix:@"/private/var/mobile/"];
}

static NSString *SDPRootPath(_SFDownloadManager *manager) {
    if (!manager || ![manager respondsToSelector:@selector(downloadsRootURL)]) {
        return nil;
    }
    @try {
        NSURL *root = [manager downloadsRootURL];
        if ([root isKindOfClass:[NSURL class]]) {
            return SDPCanonicalPath(root.path);
        }
    } @catch (__unused NSException *exception) {
        return nil;
    }
    return nil;
}

// Files still owned by a surviving record must not be unlinked.
static NSSet<NSString *> *SDPPathsStillReferenced(_SFDownloadManager *manager,
                                                 NSArray *wildcard) {
    NSMutableSet<NSString *> *kept = [NSMutableSet set];
    if (!manager || ![manager respondsToSelector:@selector(downloads)]) {
        return kept;
    }
    NSArray *remaining = nil;
    @try {
        remaining = [manager downloads];
    } @catch (__unused NSException *exception) {
        remaining = nil;
    }
    if (![remaining isKindOfClass:[NSArray class]]) {
        return kept;
    }
    for (id record in remaining) {
        if ([wildcard containsObject:record]) {
            continue;
        }
        NSString *path = SDPCanonicalPath(SDPFileURLForDownload(record).path);
        if (path.length > 0) {
            [kept addObject:path];
        }
    }
    return kept;
}

@implementation SDPPurge

+ (NSArray<NSString *> *)sdp_purgeDownloads:(NSArray *)downloads reason:(NSString *)reason {
    if (![downloads isKindOfClass:[NSArray class]] || downloads.count == 0) {
        return @[];
    }
    if (![SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES]) {
        return @[];
    }
    BOOL single = ![reason isEqualToString:@"clear-all"];
    if (single && ![SDPConfig sdp_boolForKey:@"purgeSingle" defaultValue:YES]) {
        return @[];
    }
    if ([reason isEqualToString:@"clear-all"] &&
        ![SDPConfig sdp_boolForKey:@"purgeClearAll" defaultValue:YES]) {
        return @[];
    }


    BOOL logOnly = [SDPConfig sdp_boolForKey:@"logOnly" defaultValue:NO];
    BOOL keepInstallers = [SDPConfig sdp_boolForKey:@"keepInstallers" defaultValue:YES];

    _SFDownloadManager *manager = SDPSharedManager();
    NSString *rootPath = SDPRootPath(manager);
    NSSet<NSString *> *referenced = SDPPathsStillReferenced(manager, downloads);

    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *removed = [NSMutableArray array];
    NSMutableSet<NSString *> *handled = [NSMutableSet set];
    NSMutableArray<NSString *> *deferred = [NSMutableArray array];

    for (id record in downloads) {
        NSString *path = SDPCanonicalPath(SDPFileURLForDownload(record).path);
        if (path.length == 0 || [handled containsObject:path]) {
            continue;
        }
        [handled addObject:path];

        if (![fileManager fileExistsAtPath:path]) {
            NSLog(@"[SafariDownloadPurge] skip missing file: %@", path);
            continue;
        }
        if (!SDPPathLooksLikeDownload(path, rootPath)) {
            NSLog(@"[SafariDownloadPurge] skip outside downloads: %@", path);
            continue;
        }
        if ([referenced containsObject:path]) {
            NSLog(@"[SafariDownloadPurge] skip still referenced: %@", path);
            continue;
        }
        NSString *extension = path.pathExtension.lowercaseString;
        if (keepInstallers && extension.length > 0 &&
            [SDPInstallerExtensions() containsObject:extension]) {
            NSLog(@"[SafariDownloadPurge] keep installer: %@", path);
            continue;
        }
        if (logOnly) {
            NSLog(@"[SafariDownloadPurge] log-only, would remove: %@", path);
            [removed addObject:path];
            continue;
        }

        NSError *error = nil;
        if ([fileManager removeItemAtPath:path error:&error]) {
            NSLog(@"[SafariDownloadPurge] removed: %@", path);
            [removed addObject:path];
        } else {
            // Safari may lack the sandbox extension for the Downloads container;
            // hand the path to the SpringBoard fallback instead of giving up.
            NSLog(@"[SafariDownloadPurge] deferred %@: %@", path, error.localizedDescription);
            [deferred addObject:path];
            [removed addObject:path];
        }
    }
    if (deferred.count > 0) {
        [SDPQueue sdp_enqueuePaths:deferred];
    }
    return removed;
}

@end
