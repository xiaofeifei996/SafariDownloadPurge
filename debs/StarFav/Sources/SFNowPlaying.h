#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>

extern NSString *const SFStateDidChangeNotification;

@interface SFNowPlaying : NSObject
@property (nonatomic, readonly) BOOL hasTrack;
@property (nonatomic, readonly) BOOL liked;
@property (nonatomic, readonly) BOOL canLike;
@property (nonatomic, copy) NSString *trackKey;
+ (instancetype)shared;
- (void)start;
- (void)refresh;
- (void)toggleLike;
@end
