#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <substrate.h>
#import "SDPPrivate.h"
#import "SDPConfig.h"
#import "SDPDebug.h"

// Safari does not always funnel a file removal through one method: the download
// row, the file presenter and QuickLook each reach the filesystem on their own.
// Hooking the two Foundation removal entry points guarantees the bytes survive
// when the tweak is switched off, whichever path Safari takes.

static BOOL (*SDPOrigRemovePath)(id, SEL, NSString *, NSError **);
static BOOL (*SDPOrigRemoveURL)(id, SEL, NSURL *, NSError **);
static BOOL SDPGuardInstalled = NO;

static NSString *SDPDownloadsRootPath(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        Class cls = SDPClassNamed("_SFDownloadManager");
        if (!cls) {
            return;
        }
        @try {
            id manager = ((id (*)(id, SEL))objc_msgSend)((id)cls, @selector(sharedManager));
            NSURL *url = ((id (*)(id, SEL))objc_msgSend)(manager, @selector(downloadsRootURL));
            if ([url isKindOfClass:[NSURL class]]) {
                root = [url.path copy];
            }
        } @catch (__unused NSException *exception) {
            root = nil;
        }
    });
    return root;
}

static BOOL SDPPathIsProtected(NSString *path) {
    if (path.length == 0) {
        return NO;
    }
    if ([path hasSuffix:@".sdpstash"]) {
        // Never block the tweak's own bookkeeping.
        return NO;
    }
    NSString *root = SDPDownloadsRootPath();
    if (root.length > 0) {
        NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
        if ([path hasPrefix:prefix]) {
            return YES;
        }
    }
    // Safari also keeps downloads inside its own data container; the manager may
    // report those through the same accessor, but the path shape differs, so a
    // second check keeps them covered.
    for (NSString *marker in @[@"/Downloads/", @"/Downloads", @"/Downloads "]) {
        if ([path containsString:marker]) {
            return [path hasPrefix:@"/var/mobile/"] || [path hasPrefix:@"/private/var/mobile/"];
        }
    }
    return NO;
}

// Enabled means the tweak handles deletion itself; the guard only steps in when
// the user switched it off.
static BOOL SDPShouldBlock(NSString *path) {
    if (!SDPPathIsProtected(path)) {
        return NO;
    }
    [SDPConfig sdp_synchronize];
    return ![SDPConfig sdp_boolForKey:@"enabled" defaultValue:YES];
}

static BOOL SDPDeny(NSString *path, NSError **error) {
    [SDPDebug sdp_log:@"已拦截删除（插件关闭）：%@", path];
    if (error) {
        *error = [NSError errorWithDomain:NSCocoaErrorDomain
                                     code:NSFileWriteNoPermissionError
                                 userInfo:@{
            NSFilePathErrorKey: path ?: @"",
            NSLocalizedDescriptionKey: @"Safari 下载清除同步：插件已关闭，保留该文件",
        }];
    }
    return NO;
}

static BOOL SDPRemoveItemAtPath(id self, SEL _cmd, NSString *path, NSError **error) {
    if (SDPShouldBlock(path)) {
        return SDPDeny(path, error);
    }
    return SDPOrigRemovePath ? SDPOrigRemovePath(self, _cmd, path, error) : NO;
}

static BOOL SDPRemoveItemAtURL(id self, SEL _cmd, NSURL *url, NSError **error) {
    if ([url isKindOfClass:[NSURL class]] && SDPShouldBlock(url.path)) {
        return SDPDeny(url.path, error);
    }
    return SDPOrigRemoveURL ? SDPOrigRemoveURL(self, _cmd, url, error) : NO;
}

static void SDPInstallGuard(void) {
    if (SDPGuardInstalled) {
        return;
    }
    Class manager = objc_getClass("NSFileManager");
    if (!manager) {
        return;
    }
    BOOL hooked = NO;
    Method path = class_getInstanceMethod(manager, @selector(removeItemAtPath:error:));
    if (path) {
        MSHookMessageEx(manager, @selector(removeItemAtPath:error:),
                        (IMP)SDPRemoveItemAtPath, (IMP *)&SDPOrigRemovePath);
        hooked = YES;
    }
    Method url = class_getInstanceMethod(manager, @selector(removeItemAtURL:error:));
    if (url) {
        MSHookMessageEx(manager, @selector(removeItemAtURL:error:),
                        (IMP)SDPRemoveItemAtURL, (IMP *)&SDPOrigRemoveURL);
        hooked = YES;
    }
    if (hooked) {
        SDPGuardInstalled = YES;
        [SDPDebug sdp_log:@"保护已启用（NSFileManager 删除拦截）"];
    }
}

__attribute__((constructor)) static void SDPGuardEntry(void) {
    @autoreleasepool {
        // The tweak is filtered to Safari and SafariViewService only, so this
        // always runs where a download list exists.
        SDPInstallGuard();
    }
}
