// StarFav.xm - iOS 16 lock screen / Control Center now-playing star (iOS 17 style)
#import <UIKit/UIKit.h>
#import "SFNowPlaying.h"

static NSMapTable<UIView *, UIButton *> *gStarButtons;

#pragma mark - shared target

@interface SFStarTarget : NSObject
+ (instancetype)shared;
- (void)handleTap;
@end

@implementation SFStarTarget
+ (instancetype)shared {
    static SFStarTarget *t;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ t = [[SFStarTarget alloc] init]; });
    return t;
}
- (void)handleTap {
    UIImpactFeedbackGenerator *gen = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [gen impactOccurred];
    [[SFNowPlaying shared] toggleLike];
}
@end

#pragma mark - star images

static UIImage *SFStarImage(BOOL filled) {
    UIImageSymbolConfiguration *cfg =
        [UIImageSymbolConfiguration configurationWithPointSize:19 weight:UIImageSymbolWeightMedium];
    UIImage *img = [UIImage systemImageNamed:(filled ? @"star.fill" : @"star") withConfiguration:cfg];
    return [img imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
}

#pragma mark - helpers

static UIButton *SFButtonForStack(UIView *stack) {
    if (!gStarButtons) {
        gStarButtons = [NSMapTable mapTableWithKeyOptions:NSPointerFunctionsWeakMemory
                                             valueOptions:NSPointerFunctionsStrongMemory];
    }
    UIButton *btn = [gStarButtons objectForKey:stack];
    if (btn) return btn;

    btn = [UIButton buttonWithType:UIButtonTypeCustom];
    btn.bounds = CGRectMake(0, 0, 44, 44);
    btn.exclusiveTouch = NO;
    [btn setImage:SFStarImage(NO) forState:UIControlStateNormal];
    btn.tintColor = [UIColor colorWithWhite:1.0 alpha:0.92];
    [btn addTarget:[SFStarTarget shared]
            action:@selector(handleTap)
  forControlEvents:UIControlEventTouchUpInside];
    [stack addSubview:btn];
    [gStarButtons setObject:btn forKey:stack];
    return btn;
}

static void SFUpdateButtonImages(void) {
    SFNowPlaying *s = [SFNowPlaying shared];
    for (UIView *stack in gStarButtons) {
        UIButton *btn = [gStarButtons objectForKey:stack];
        if (!btn) continue;
        [btn setImage:SFStarImage(s.liked) forState:UIControlStateNormal];
        if (!s.hasTrack || !s.canLike) {
            btn.hidden = YES;
        } else if (CGPointEqualToPoint(btn.center, CGPointZero)) {
            [btn.superview setNeedsLayout];
        } else {
            btn.hidden = NO;
        }
    }
}

static void SFLayoutStar(id stackView) {
    UIView *stack = (UIView *)stackView;
    SFNowPlaying *s = [SFNowPlaying shared];
    UIButton *btn = SFButtonForStack(stack);

    // anchor: native transport button (both MediaControls + MRU stacks expose leftButton)
    UIView *anchor = nil;
    if ([stack respondsToSelector:NSSelectorFromString(@"leftButton")]) {
        anchor = [stack valueForKey:@"leftButton"];
    }

    BOOL visible = s.hasTrack && s.canLike;
    if (anchor && (anchor.hidden || anchor.alpha < 0.02)) visible = NO;
    if (!anchor || CGRectIsEmpty(anchor.frame)) {
        btn.hidden = !visible;
        if (visible) {
            btn.center = CGPointMake(24, CGRectGetMidY(stack.bounds));
        }
        return;
    }

    btn.hidden = !visible;
    if (!visible) return;

    CGRect af = anchor.frame;      // frame in stack coordinates
    CGFloat gap = 6.0;
    CGFloat w = CGRectGetWidth(btn.bounds);
    CGFloat cx = CGRectGetMinX(af) - gap - w / 2.0;
    CGFloat cy = CGRectGetMidY(af);
    btn.center = CGPointMake(cx, cy);
    btn.tintColor = anchor.tintColor ?: [UIColor colorWithWhite:1.0 alpha:0.92];
}

#pragma mark - hooks

%hook MediaControlsTransportStackView

- (void)layoutSubviews {
    %orig;
    SFLayoutStar(self);
}

- (void)setResponse:(id)response {
    %orig;
    [[SFNowPlaying shared] refresh];
}

%end

%hook MRUNowPlayingTransportControlsView

- (void)layoutSubviews {
    %orig;
    SFLayoutStar(self);
}

- (void)setTransportControls:(id)controls {
    %orig;
    [[SFNowPlaying shared] refresh];
}

%end

%ctor {
    @autoreleasepool {
        [[SFNowPlaying shared] start];
        [[NSNotificationCenter defaultCenter]
            addObserverForName:SFStateDidChangeNotification
                        object:nil
                         queue:[NSOperationQueue mainQueue]
                    usingBlock:^(NSNotification *note) {
            SFUpdateButtonImages();
        }];
    }
}
