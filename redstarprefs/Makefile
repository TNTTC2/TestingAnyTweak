TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RedStar

RedStar_FILES = RedStarRootListController.m
RedStar_FRAMEWORKS = UIKit
RedStar_PRIVATE_FRAMEWORKS = Preferences
RedStar_INSTALL_PATH = /Library/PreferenceBundles
RedStar_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
