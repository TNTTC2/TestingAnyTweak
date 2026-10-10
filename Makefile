TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = AppBeforeX

AppBeforeX_FILES = Tweak.x
AppBeforeX_CFLAGS = -fobjc-arc
AppBeforeX_FRAMEWORKS = UIKit Foundation

SUBPROJECTS += appbeforexprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
include $(THEOS_MAKE_PATH)/tweak.mk
