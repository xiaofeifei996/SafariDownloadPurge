DEBUG = 0
FINALPACKAGE = 1

ARCHS = arm64 arm64e

include SDPBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SafariDownloadPurge
SafariDownloadPurge_FILES = $(wildcard Hooks/*.mm Sources/*.m)
SafariDownloadPurge_CFLAGS = -fobjc-arc -I./Headers -I./Sources \
	-DSDP_BUILD_STAMP='@"1.1.4"'
SafariDownloadPurge_FRAMEWORKS = UIKit Foundation CoreFoundation
SafariDownloadPurge_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk

SUBPROJECTS += SDPPrefs
include $(THEOS_MAKE_PATH)/aggregate.mk
