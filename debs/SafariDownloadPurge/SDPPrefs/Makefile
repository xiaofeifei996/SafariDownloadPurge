include ../SDPBuild.mk
include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = SDPPrefs
SDPPrefs_FILES = $(wildcard *.m)
SDPPrefs_CFLAGS = -fobjc-arc -I../Sources
SDPPrefs_FRAMEWORKS = UIKit Foundation CoreFoundation
SDPPrefs_PRIVATE_FRAMEWORKS = Preferences
SDPPrefs_INSTALL_PATH = /Library/PreferenceBundles

include $(THEOS_MAKE_PATH)/bundle.mk
