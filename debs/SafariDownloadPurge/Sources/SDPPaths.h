#pragma once

#import <Foundation/Foundation.h>

// Every place a preference copy can live, ordered so the most authoritative
// store for the calling process comes first.
//
// A sandboxed app such as Safari may have its CFPreferences domain resolved
// inside its own data container, while Settings writes to
// /var/mobile/Library/Preferences. The panel therefore mirrors the value into
// the app containers, and readers prefer their own container copy.
NSArray<NSString *> *SDPPreferenceReadPaths(void);
NSArray<NSString *> *SDPPreferenceWritePaths(void);

// Containers of processes this tweak runs inside (Safari, SpringBoard).
NSArray<NSString *> *SDPInjectedContainerPreferencePaths(void);

NSString *SDPCanonicalPreferencePath(void);
