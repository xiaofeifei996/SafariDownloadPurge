#import "SDPProtect.h"
#import "SDPDebug.h"

// A hard link is used instead of a copy: it is instant and costs no space, and
// it survives the original being unlinked because the inode stays alive.
//
// The links live in one private directory rather than next to the originals:
// Safari wipes its Downloads folder wholesale, which would take the parked
// copies with it. A sibling file name is still recorded so the original path
// can be rebuilt.
static NSString *const SDPStashSuffix = @".sdpstash";
static NSString *const SDPStashDirectory = @"/var/mobile/Library/SafariDownloadPurge/Stash";

static NSString *SDPStashPath(NSString *path) {
    NSString *name = [path stringByReplacingOccurrencesOfString:@"/" withString:@"__"];
    return [SDPStashDirectory stringByAppendingPathComponent:
            [name stringByAppendingString:SDPStashSuffix]];
}

static NSString *SDPOriginalPathFromStash(NSString *stashPath) {
    NSString *name = [stashPath.lastPathComponent stringByDeletingPathExtension];
    if ([name hasSuffix:@".sdpstash"]) {
        name = [name substringToIndex:name.length - SDPStashSuffix.length];
    }
    return [name stringByReplacingOccurrencesOfString:@"__" withString:@"/"];
}

// Files Safari may remove along with the list entry.
@implementation SDPProtect

+ (NSUInteger)sdp_stashPaths:(NSArray<NSString *> *)paths {
    NSFileManager *manager = [NSFileManager defaultManager];
    [manager createDirectoryAtPath:SDPStashDirectory
       withIntermediateDirectories:YES attributes:nil error:NULL];
    NSUInteger stashed = 0;
    for (NSString *path in paths) {
        if (path.length == 0) {
            continue;
        }
        BOOL isDirectory = NO;
        if (![manager fileExistsAtPath:path isDirectory:&isDirectory] || isDirectory) {
            continue;
        }
        NSString *stash = SDPStashPath(path);
        [manager removeItemAtPath:stash error:NULL];
        NSError *error = nil;
        if ([manager linkItemAtPath:path toPath:stash error:&error]) {
            stashed++;
            [SDPDebug sdp_log:@"保护：已暂存 %@", path];
        } else {
            [SDPDebug sdp_log:@"保护失败 %@：%@", path, error.localizedDescription];
        }
    }
    return stashed;
}

+ (NSUInteger)sdp_restorePaths:(NSArray<NSString *> *)paths {
    NSFileManager *manager = [NSFileManager defaultManager];
    NSUInteger restored = 0;
    for (NSString *path in paths) {
        if (path.length == 0) {
            continue;
        }
        NSString *stash = SDPStashPath(path);
        BOOL stashExists = [manager fileExistsAtPath:stash];
        if (!stashExists) {
            continue;
        }
        if ([manager fileExistsAtPath:path]) {
            // Original survived; the park copy is no longer needed.
            [manager removeItemAtPath:stash error:NULL];
            continue;
        }
        NSError *error = nil;
        // The guard blocks deletions, not renames, so this still works with the
        // tweak switched off.
        if ([manager moveItemAtPath:stash toPath:path error:&error]) {
            restored++;
            [SDPDebug sdp_log:@"保护：已还原 %@", path];
        } else {
            [SDPDebug sdp_log:@"还原失败 %@：%@", path, error.localizedDescription];
        }
    }
    return restored;
}

+ (NSUInteger)sdp_restoreAllStashesUnderRoot:(NSString *)rootPath {
    if (rootPath.length == 0) {
        return 0;
    }
    NSFileManager *manager = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *paths = [NSMutableArray array];
    for (NSString *name in [manager contentsOfDirectoryAtPath:SDPStashDirectory error:NULL]) {
        if (![name hasSuffix:SDPStashSuffix]) {
            continue;
        }
        NSString *stash = [SDPStashDirectory stringByAppendingPathComponent:name];
        [paths addObject:SDPOriginalPathFromStash(stash)];
    }
    return [self sdp_restorePaths:paths];
}

@end
