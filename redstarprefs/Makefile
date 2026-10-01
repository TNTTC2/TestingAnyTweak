TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RedStarPrefs

RedStarPrefs_FILES = RedStarRootListController.m
RedStarPrefs_FRAMEWORKS = UIKit
RedStarPrefs_PRIVATE_FRAMEWORKS = Preferences
RedStarPrefs_INSTALL_PATH = /Library/PreferenceBundles
RedStarPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
