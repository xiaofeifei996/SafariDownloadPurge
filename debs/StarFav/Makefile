DEBUG = 0
FINALPACKAGE = 1

include SFBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = StarFav
StarFav_FILES = $(wildcard Hooks/*.xm) $(wildcard Sources/*.m)
StarFav_CFLAGS = -fobjc-arc -I./Sources
StarFav_FRAMEWORKS = UIKit Foundation CoreFoundation
StarFav_LIBRARIES = substrate

include $(THEOS_MAKE_PATH)/tweak.mk
