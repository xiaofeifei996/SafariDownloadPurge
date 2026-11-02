#import "SDPToast.h"
#import "SDPPurge.h"
#import <UIKit/UIKit.h>

static void SDPShowToast(NSString *text) {
    if (text.length == 0) {
        return;
    }
    dispatch_async(dispatch_get_main_queue(), ^{
        UIWindow *window = nil;
        for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *candidate in windowScene.windows) {
                if (candidate.isKeyWindow) {
                    window = candidate;
                    break;
                }
            }
            if (!window && windowScene.windows.count > 0) {
                window = windowScene.windows.firstObject;
            }
            if (window) {
                break;
            }
        }
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
        label.text = text;
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

@implementation SDPToast

+ (void)sdp_showRemovedCount:(NSUInteger)count {
    if (count == 0) {
        return;
    }
    SDPShowToast([NSString stringWithFormat:@"已同步删除 %lu 个文件", (unsigned long)count]);
}

+ (void)sdp_showReport:(NSDictionary<NSString *, NSNumber *> *)report {
    if (![report isKindOfClass:[NSDictionary class]] || report.count == 0) {
        return;
    }
    NSMutableArray<NSString *> *parts = [NSMutableArray array];
    NSUInteger removed = [report[SDPPurgeReportRemoved] unsignedIntegerValue];
    NSUInteger deferred = [report[SDPPurgeReportDeferred] unsignedIntegerValue];
    NSUInteger logOnly = [report[SDPPurgeReportLogOnly] unsignedIntegerValue];
    NSUInteger kept = [report[SDPPurgeReportKeptInstaller] unsignedIntegerValue];

    if (removed > deferred) {
        [parts addObject:[NSString stringWithFormat:@"已删除 %lu 个",
                          (unsigned long)(removed - deferred)]];
    }
    if (deferred > 0) {
        [parts addObject:[NSString stringWithFormat:@"转入兜底 %lu 个", (unsigned long)deferred]];
    }
    if (kept > 0) {
        [parts addObject:[NSString stringWithFormat:@"保留安装包 %lu 个", (unsigned long)kept]];
    }
    if (logOnly > 0) {
        [parts addObject:[NSString stringWithFormat:@"只记录未删除 %lu 个", (unsigned long)logOnly]];
    }
    if (parts.count == 0) {
        return;
    }
    SDPShowToast([parts componentsJoinedByString:@"，"]);
}

+ (void)sdp_showProtectedCount:(NSUInteger)count {
    if (count == 0) {
        return;
    }
    SDPShowToast([NSString stringWithFormat:@"插件已关闭，已还原 %lu 个文件",
                  (unsigned long)count]);
}

@end
