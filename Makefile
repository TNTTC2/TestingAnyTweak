TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = ScreenMySaver

ScreenMySaver_FILES = Tweak.x
ScreenMySaver_CFLAGS = -fobjc-arc
ScreenMySaver_LDFLAGS = -Wl,-undefined,dynamic_lookup
ScreenMySaver_FRAMEWORKS = UIKit CoreGraphics

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += screenmysaverprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
