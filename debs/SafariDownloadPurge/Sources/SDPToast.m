#import "SDPToast.h"
#import <UIKit/UIKit.h>

@implementation SDPToast

+ (UIWindow *)sdp_keyWindow {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) {
            continue;
        }
        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (window.isKeyWindow) {
                return window;
            }
        }
    }
    return [UIApplication sharedApplication].windows.firstObject;
}

+ (void)sdp_showRemovedCount:(NSUInteger)count {
    if (count == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = [self sdp_keyWindow];
        if (!window) {
            return;
        }

        UIView *container = [[UIView alloc] init];
        container.translatesAutoresizingMaskIntoConstraints = NO;
        container.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.9];
        container.layer.cornerRadius = 14;
        container.layer.masksToBounds = YES;

        UILabel *label = [[UILabel alloc] init];
        label.translatesAutoresizingMaskIntoConstraints = NO;
        label.text = [NSString stringWithFormat:@"已同步删除 %lu 个文件", (unsigned long)count];
        label.font = [UIFont preferredFontForTextStyle:UIFontTextStyleSubheadline];
        label.textColor = UIColor.whiteColor;
        label.textAlignment = NSTextAlignmentCenter;
        label.numberOfLines = 2;
        [container addSubview:label];
        [window addSubview:container];

        UILayoutGuide *safe = window.safeAreaLayoutGuide;
        [NSLayoutConstraint activateConstraints:@[
            [label.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:16],
            [label.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-16],
            [label.topAnchor constraintEqualToAnchor:container.topAnchor constant:10],
            [label.bottomAnchor constraintEqualToAnchor:container.bottomAnchor constant:-10],
            [container.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
            [container.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-24],
            [container.widthAnchor constraintLessThanOrEqualToAnchor:window.widthAnchor
                                                           constant:-48],
        ]];

        container.alpha = 0;
        container.transform = CGAffineTransformMakeTranslation(0, 12);
        UIView *toast = container;
        [UIView animateWithDuration:0.22 animations:^{
            toast.alpha = 1;
            toast.transform = CGAffineTransformIdentity;
        } completion:^(__unused BOOL finished) {
            [UIView animateWithDuration:0.3 delay:1.6 options:0 animations:^{
                toast.alpha = 0;
            } completion:^(__unused BOOL done) {
                [toast removeFromSuperview];
            }];
        }];
    });
}

@end
