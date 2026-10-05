ARCHS = arm64
TARGET := iphone:clang:16.5:15.0
INSTALL_TARGET_PROCESSES = SpringBoard

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

TWEAK_NAME = DynamicMainland

DynamicMainland_FILES = Tweak.x
DynamicMainland_CFLAGS = -fobjc-arc
DynamicMainland_FRAMEWORKS = UIKit Foundation
DynamicMainland_PRIVATE_FRAMEWORKS = SpringBoardServices

include $(THEOS_MAKE_PATH)/tweak.mk
