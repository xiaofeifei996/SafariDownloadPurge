// SFNowPlaying.m - MediaRemote bridge: now playing state + like command
#import "SFNowPlaying.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>

typedef void (*MRGetInfoFunc)(dispatch_queue_t, void (^)(CFDictionaryRef));
typedef Boolean (*MRSendCommandFunc)(uint32_t, CFDictionaryRef);

static MRGetInfoFunc SFGetInfo = NULL;
static MRSendCommandFunc SFSendCommand = NULL;

NSString *const SFStateDidChangeNotification = @"com.axs.starfav.statechanged";

static NSString *const kSFKeyTitle       = @"kMRMediaRemoteNowPlayingInfoTitle";
static NSString *const kSFKeyArtist      = @"kMRMediaRemoteNowPlayingInfoArtist";
static NSString *const kSFKeyIsLiked     = @"kMRMediaRemoteNowPlayingInfoIsLiked";
static NSString *const kSFKeySupportsLike = @"kMRMediaRemoteNowPlayingInfoSupportsIsLiked";
static NSString *const kSFKeyUniqueID    = @"kMRMediaRemoteNowPlayingInfoUniqueIdentifier";
static NSString *const kSFKeyContentID   = @"kMRMediaRemoteNowPlayingInfoContentItemIdentifier";
static NSString *const kSFKeyStoreID     = @"kMRMediaRemoteNowPlayingInfoiTunesStoreIdentifier";

static NSString *const kSFPrefsDomain = @"com.axs.starfav";
static NSString *const kSFPrefsKey    = @"likeState";

static void SFNotificationCallback(CFNotificationCenterRef center, void *observer,
                                   CFStringRef name, const void *object,
                                   CFDictionaryRef userInfo) {
    dispatch_async(dispatch_get_main_queue(), ^{
        [[SFNowPlaying shared] refresh];
    });
}

static BOOL SFResolveSymbols(void) {
    if (SFGetInfo && SFSendCommand) return YES;
    void *h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY);
    void *lookup = h ? h : RTLD_DEFAULT;
    if (!SFGetInfo) SFGetInfo = (MRGetInfoFunc)dlsym(lookup, "MRMediaRemoteGetNowPlayingInfo");
    if (!SFSendCommand) SFSendCommand = (MRSendCommandFunc)dlsym(lookup, "MRMediaRemoteSendCommand");
    return (SFGetInfo != NULL);
}

@implementation SFNowPlaying {
    NSMutableDictionary<NSString *, NSNumber *> *_likeCache;
    BOOL _hasTrack;
    BOOL _liked;
    BOOL _canLike;
    BOOL _refreshing;
}

+ (instancetype)shared {
    static SFNowPlaying *inst;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ inst = [[SFNowPlaying alloc] init]; });
    return inst;
}

- (instancetype)init {
    if ((self = [super init])) {
        _canLike = YES;
        _likeCache = [NSMutableDictionary dictionary];
    }
    return self;
}

- (void)start {
    SFResolveSymbols();
    [self loadCache];

    NSArray *names = @[
        @"kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        @"kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
    ];
    for (NSString *n in names) {
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(),
                                        (__bridge const void *)self,
                                        SFNotificationCallback,
                                        (__bridge CFStringRef)n,
                                        NULL,
                                        CFNotificationSuspensionBehaviorDeliverImmediately);
    }
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [self refresh];
    });
}

#pragma mark - state

- (BOOL)hasTrack { return _hasTrack; }
- (BOOL)liked { return _liked; }
- (BOOL)canLike { return _canLike; }

- (void)refresh {
    if (_refreshing) return;
    if (!SFResolveSymbols()) return;
    _refreshing = YES;
    __weak typeof(self) weakSelf = self;
    SFGetInfo(dispatch_get_main_queue(), ^(CFDictionaryRef info) {
        typeof(self) self_ = weakSelf;
        if (!self_) return;
        self_->_refreshing = NO;
        [self_ handleInfo:(__bridge NSDictionary *)info];
    });
    // watchdog: never stay locked if the reply never arrives
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3.0 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        typeof(self) self_ = weakSelf;
        if (self_ && self_->_refreshing) self_->_refreshing = NO;
    });
}

- (void)handleInfo:(NSDictionary *)d {
    BOOL hasTrack = NO, liked = NO, canLike = YES;
    NSString *key = nil;

    if ([d isKindOfClass:[NSDictionary class]]) {
        NSString *title  = d[kSFKeyTitle];
        NSString *artist = d[kSFKeyArtist];
        id uid           = d[kSFKeyUniqueID];
        id contentId     = d[kSFKeyContentID];
        id storeId       = d[kSFKeyStoreID];
        NSNumber *supports = d[kSFKeySupportsLike];
        NSNumber *likedNum = d[kSFKeyIsLiked];

        hasTrack = (title.length > 0) || (uid != nil);
        if (supports != nil) canLike = supports.boolValue;

        if (contentId != nil)      key = [[contentId description] copy];
        else if (uid != nil)       key = [[uid description] copy];
        else if (storeId != nil)   key = [[storeId description] copy];
        else if (title.length)     key = [NSString stringWithFormat:@"%@|%@", title, artist ?: @""];

        if (likedNum != nil) {
            liked = likedNum.boolValue;
        } else if (key && _likeCache[key]) {
            liked = [_likeCache[key] boolValue];
        }
    }

    if (!hasTrack) canLike = NO;
    if (!canLike) liked = NO;

    self.trackKey = key;

    BOOL changed = (hasTrack != _hasTrack) || (liked != _liked) || (canLike != _canLike);
    _hasTrack = hasTrack;
    _liked = liked;
    _canLike = canLike;
    if (changed) {
        [[NSNotificationCenter defaultCenter] postNotificationName:SFStateDidChangeNotification object:self];
    }
}

#pragma mark - action

- (void)toggleLike {
    if (!_hasTrack || !_canLike) return;
    BOOL newVal = !_liked;
    _liked = newVal;
    if (self.trackKey) {
        _likeCache[self.trackKey] = @(newVal);
        [self saveCache];
    }
    [[NSNotificationCenter defaultCenter] postNotificationName:SFStateDidChangeNotification object:self];

    if (!SFResolveSymbols()) return;
    if (SFSendCommand) {
        SFSendCommand(21 /* MRMediaRemoteCommandLikeTrack */, NULL);
    }
    // 汽水音乐桥接：让注入汽水的 SFBridge 触发 App 内收藏按钮
    CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                         CFSTR("com.axs.starfav.toggle"),
                                         NULL, NULL, YES);
    __weak typeof(self) weakSelf = self;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.7 * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        [weakSelf refresh];
    });
}

#pragma mark - persistence

- (void)loadCache {
    CFPropertyListRef v = CFPreferencesCopyAppValue((__bridge CFStringRef)kSFPrefsKey,
                                                    (__bridge CFStringRef)kSFPrefsDomain);
    if ([(__bridge id)v isKindOfClass:[NSDictionary class]]) {
        _likeCache = [(__bridge NSDictionary *)v mutableCopy];
    }
    if (v) CFRelease(v);
}

- (void)saveCache {
    CFPreferencesSetAppValue((__bridge CFStringRef)kSFPrefsKey,
                             (__bridge CFPropertyListRef)_likeCache,
                             (__bridge CFStringRef)kSFPrefsDomain);
    CFPreferencesAppSynchronize((__bridge CFStringRef)kSFPrefsDomain);
}

@end
