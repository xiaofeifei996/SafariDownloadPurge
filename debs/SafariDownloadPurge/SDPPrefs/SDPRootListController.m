#import "SDPRootListController.h"
#import "SDPConfig.h"
#import "SDPQueue.h"
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
        _specifiers = items;
    }
    return _specifiers;
}

- (NSString *)sdp_diagnosticsText {
    NSString *pending = [NSString stringWithFormat:@"待清理队列：%lu 项\n\n",
                         (unsigned long)[SDPQueue sdp_pendingCount]];
    return [pending stringByAppendingString:[SDPConfig sdp_diagnostics]];
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
    [self reloadSpecifiers];
}

@end
