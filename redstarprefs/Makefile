TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = RedStarPrefs

RedStarPrefs_FILES = RedStarRootListController.m
RedStarPrefs_FRAMEWORKS = UIKit
RedStarPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
RedStarPrefs_INSTALL_PATH = /Library/PreferenceBundles
RedStarPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

# 打包時自動將 Entry.plist 複製到 PreferenceLoader 搜尋路徑
internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/RedStarPrefs.plist$(ECHO_END)
