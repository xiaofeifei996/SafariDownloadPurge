DEBUG = 0
FINALPACKAGE = 1

include SFBuild.mk
include $(THEOS)/makefiles/common.mk

TWEAK_NAME = SFQuery
SFQuery_FILES = SFQuery.m
SFQuery_CFLAGS = -fobjc-arc
SFQuery_FRAMEWORKS = Foundation CoreFoundation

include $(THEOS_MAKE_PATH)/tweak.mk
