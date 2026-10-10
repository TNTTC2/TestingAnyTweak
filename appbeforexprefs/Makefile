TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = AppBeforeXPrefs

AppBeforeXPrefs_FILES = AppBeforeXRootListController.m AppBeforeXAppsListController.m
AppBeforeXPrefs_FRAMEWORKS = UIKit
AppBeforeXPrefs_PRIVATE_FRAMEWORKS = Preferences
AppBeforeXPrefs_INSTALL_PATH = /Library/PreferenceBundles
AppBeforeXPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
