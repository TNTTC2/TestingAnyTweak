TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = RedStar

RedStar_FILES = Tweak.x
RedStar_CFLAGS = -fobjc-arc
RedStar_FRAMEWORKS = UIKit CoreGraphics

include $(THEOS)/makefiles/tweak.mk
SUBPROJECTS += redstarprefs
include $(THEOS_MAKE_PATH)/aggregate.mk
