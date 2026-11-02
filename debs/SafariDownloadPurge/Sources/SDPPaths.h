#pragma once

#import <Foundation/Foundation.h>

// Every place a preference copy can live, ordered so the most authoritative
// store for the calling process comes first.
//
// Safari and Settings sit in different sandboxes and do not always share a
// preference store, so both read one flat file outside any sandbox first. The
// copies below it exist only for compatibility with earlier installs.
NSArray<NSString *> *SDPPreferenceReadPaths(void);
NSArray<NSString *> *SDPPreferenceWritePaths(void);

// The flat file that every process can read and write.
NSString *SDPSharedStatePath(void);
NSArray<NSString *> *SDPSharedStatePaths(void);

// The master switch expressed as file existence. Setting a flag has to survive
// caches, sandbox containers and type coercion, and a file that either exists or
// does not is the least ambiguous way to express "off".
NSString *SDPDisabledMarkerPath(void);
BOOL SDPDisabledMarkerPresent(void);
void SDPSetDisabledMarker(BOOL disabled);

// Containers of the processes this tweak runs inside (Safari, SafariViewService).
NSArray<NSString *> *SDPInjectedContainerPreferencePaths(void);

NSString *SDPCanonicalPreferencePath(void);
