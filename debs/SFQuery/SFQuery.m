// SFQuery.m - SpringBoard probe: dump the now-playing app's supported MediaRemote commands.
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <dlfcn.h>

typedef void (*MRCopySupportedCmdsFunc)(dispatch_queue_t, void (^)(CFArrayRef));
typedef void (*MRGetInfoFunc)(dispatch_queue_t, void (^)(CFDictionaryRef));

static MRCopySupportedCmdsFunc QueryCmds = NULL;
static MRGetInfoFunc GetInfo = NULL;

static void SFWriteReport(NSString *text) {
    // SpringBoard 沙盒里 CFPreferences 稳定可写（StarFav 已验证）
    CFPreferencesSetAppValue(CFSTR("report"), (__bridge CFPropertyListRef)text,
                             CFSTR("com.axs.sfquery"));
    CFPreferencesAppSynchronize(CFSTR("com.axs.sfquery"));
    // 同时尝试写 Documents（若沙盒允许）
    [text writeToFile:@("/var/mobile/Documents/sfquery.txt")
           atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    NSLog(@"[SFQuery] %@", [text length] > 3000 ? @"(long)" : text);
}

static NSString *SFDescribeDict(CFDictionaryRef d) {
    if (!d) return @"(null)";
    NSDictionary *dict = (__bridge NSDictionary *)d;
    NSMutableString *out = [NSMutableString string];
    for (NSString *k in dict) {
        id v = dict[k];
        [out appendFormat:@"%@ = %@\n", k, [v description]];
    }
    return out;
}

__attribute__((constructor)) static void SFQueryInit(void) {
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(4 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
        if (!h) { SFWriteReport(@"dlopen MediaRemote failed"); return; }
        QueryCmds = (MRCopySupportedCmdsFunc)dlsym(h, "MRMediaRemoteCopySupportedCommands");
        GetInfo    = (MRGetInfoFunc)dlsym(h, "MRMediaRemoteGetNowPlayingInfo");
        if (!QueryCmds) { SFWriteReport(@"symbol not found"); return; }

        NSMutableString *report = [NSMutableString stringWithFormat:
            @"=== SFQuery pid=%d time=%@ ===\n", getpid(),
            [NSDate date]];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        QueryCmds(dispatch_get_main_queue(), ^(CFArrayRef cmds) {
            [report appendFormat:@"SUPPORTED COMMANDS: %@\n", (__bridge NSArray *)cmds];
            dispatch_semaphore_signal(sem);
        });
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));

        if (GetInfo) {
            GetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
                [report appendFormat:@"NOW PLAYING INFO:\n%@", SFDescribeDict(info)];
                dispatch_semaphore_signal(sem);
            });
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)));
        }

        [report appendString:@"QUERY_DONE\n"];
        SFWriteReport(report);
    });
}
