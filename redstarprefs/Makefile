TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RedStarPrefs

RedStarPrefs_FILES = RedStarRootListController.m
RedStarPrefs_FRAMEWORKS = UIKit

# 1. 移除原本的 RedStarPrefs_PRIVATE_FRAMEWORKS = Preferences
# 2. 加入以下這行 Linker 旗標：
RedStarPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup

RedStarPrefs_INSTALL_PATH = /Library/PreferenceBundles
RedStarPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk
