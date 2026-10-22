TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = PressHB

PressHB_FILES = Tweak.x
PressHB_CFLAGS = -fobjc-arc
PressHB_LDFLAGS = -Wl,-undefined,dynamic_lookup
PressHB_FRAMEWORKS = UIKit CoreGraphics AudioToolbox

include $(THEOS_MAKE_PATH)/tweak.mk
SUBPROJECTS += presshbprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
