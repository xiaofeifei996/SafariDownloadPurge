#import "SDPRootListController.h"
#import "SDPConfig.h"
#import <Preferences/PSSpecifier.h>
#import <UIKit/UIKit.h>

@interface SDPRootListController ()
@end

@implementation SDPRootListController

- (NSMutableArray *)specifiers {
    if (!_specifiers) {
        NSMutableArray *items = [[self loadSpecifiersFromPlistName:@"SDPRoot"
                                                           target:self] mutableCopy];
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

@end
