#import "SDPRootListController.h"
#import "SDPConfig.h"
#import "SDPQueue.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface SDPRootListController ()
@end

@implementation SDPRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"SDPRoot"
                                                           target:self] mutableCopy];
        [items addObject:[PSSpecifier preferenceSpecifierNamed:@"运行状态与存储"
                                                        target:self
                                                           set:nil
                                                           get:@selector(readDiagnostics:)
                                                        detail:nil
                                                          cell:PSGroupCell
                                                          edit:nil]];
        _specifiers = items;
    }
    return _specifiers;
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
}

- (id)readDiagnostics:(PSSpecifier *)specifier {
    (void)specifier;
    NSString *pending = [NSString stringWithFormat:@"待清理队列：%lu 项",
                         (unsigned long)[SDPQueue sdp_pendingCount]];
    return [NSString stringWithFormat:@"%@\n\n%@", pending, [SDPConfig sdp_diagnostics]];
}

// Keep the diagnostics footer current after every toggle.
- (void)reloadSpecifiers {
    [super reloadSpecifiers];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self reloadSpecifiers];
}

@end
