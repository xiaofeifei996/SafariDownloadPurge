include ../SDPBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SDPPrefs
SDPPrefs_FILES = $(wildcard *.m) ../Sources/SDPConfig.m ../Sources/SDPPaths.m ../Sources/SDPQueue.m
SDPPrefs_CFLAGS = -fobjc-arc -I../Sources
SDPPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
SDPPrefs_PRIVATE_FRAMEWORKS = Preferences
SDPPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
SDPPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
