#import "SDPRootListController.h"
#import "SDPConfig.h"
#import "SDPQueue.h"
#import "SDPDebug.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface SDPRootListController ()
@property (nonatomic, strong) PSSpecifier *diagnosticsSpecifier;
@end

@implementation SDPRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"SDPRoot"
                                                           target:self] mutableCopy];

        // A group cell renders its footer only from the footerText property, so
        // the diagnostics text is assigned here instead of fetched.
        PSSpecifier *diagnostics = [PSSpecifier preferenceSpecifierNamed:@"运行状态"
                                                                 target:self
                                                                    set:nil
                                                                    get:nil
                                                                 detail:nil
                                                                   cell:PSGroupCell
                                                                   edit:nil];
        [diagnostics setProperty:[self sdp_diagnosticsText] forKey:@"footerText"];
        self.diagnosticsSpecifier = diagnostics;
        [items addObject:diagnostics];

        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"日志"
                                                        target:self
                                                           set:nil
                                                           get:nil
                                                        detail:nil
                                                          cell:PSGroupCell
                                                          edit:nil]];
        [self sdp_addButton:@"查看运行日志" action:@selector(sdp_showLog:) to:items];
        [self sdp_addButton:@"清空日志" action:@selector(sdp_clearLog:) to:items];

        _specifiers = items;
    }
    return _specifiers;
}

- (void)sdp_addButton:(NSString *)title action:(SEL)action to:(NSMutableArray *)items {
    PSSpecifier *button = [PSSpecifier preferenceSpecifierNamed:title
                                                         target:self
                                                            set:nil
                                                            get:nil
                                                         detail:nil
                                                           cell:PSButtonCell
                                                           edit:nil];
    button.buttonAction = action;
    [items addObject:button];
}

- (NSString *)sdp_diagnosticsText {
    BOOL hooked = [SDPConfig sdp_boolForKey:@"hookInstalled" defaultValue:NO];
    NSString *head = [NSString stringWithFormat:@"Safari 内 Hook：%@\n待清理队列：%lu 项\n\n",
                      hooked ? @"已安装" : @"尚未安装（先在 Safari 打开一次下载列表）",
                      (unsigned long)[SDPQueue sdp_pendingCount]];
    return [head stringByAppendingString:[SDPConfig sdp_diagnostics]];
}

- (void)sdp_showLog:(id)sender {
    UITextView *view = [[UITextView alloc] initWithFrame:CGRectZero];
    view.editable = NO;
    view.font = [UIFont monospacedSystemFontOfSize:11 weight:UIFontWeightRegular];
    view.text = [SDPDebug sdp_recentLogWithLimit:120];
    view.textContainerInset = UIEdgeInsetsMake(12, 12, 12, 12);

    UIViewController *controller = [[UIViewController alloc] init];
    controller.title = @"运行日志";
    controller.view.backgroundColor = UIColor.systemBackgroundColor;
    view.translatesAutoresizingMaskIntoConstraints = NO;
    [controller.view addSubview:view];
    [NSLayoutConstraint activateConstraints:@[
        [view.topAnchor constraintEqualToAnchor:controller.view.topAnchor],
        [view.bottomAnchor constraintEqualToAnchor:controller.view.bottomAnchor],
        [view.leadingAnchor constraintEqualToAnchor:controller.view.leadingAnchor],
        [view.trailingAnchor constraintEqualToAnchor:controller.view.trailingAnchor],
    ]];
    [self.navigationController pushViewController:controller animated:YES];
}

- (void)sdp_clearLog:(id)sender {
    [SDPDebug sdp_clearLog];
    [self reloadSpecifiers];
}

- (id)readPreferenceValue:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) {
        return nil;
    }
    BOOL fallback = [[specifier propertyForKey:@"default"] boolValue];
    return @([SDPConfig sdp_boolForKey:key defaultValue:fallback]);
}

- (void)setPreferenceValue:(id)value specifier:(PSSpecifier *)specifier {
    NSString *key = [specifier propertyForKey:@"key"];
    if (key.length == 0) {
        return;
    }
    [SDPConfig sdp_setBool:[value boolValue] forKey:key];

    // Keep the diagnostics footer in step with the toggle just flipped.
    PSSpecifier *diagnostics = self.diagnosticsSpecifier;
    if (diagnostics) {
        [diagnostics setProperty:[self sdp_diagnosticsText] forKey:@"footerText"];
        [self reloadSpecifier:diagnostics animated:NO];
    }
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Applies pending key normalisation before the switches are read.
    [SDPConfig sdp_migrateIfNeeded];
    [self reloadSpecifiers];
}

@end
