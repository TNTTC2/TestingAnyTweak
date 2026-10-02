TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = ScreenMySaverPrefs

ScreenMySaverPrefs_FILES = ScreenMySaverRootListController.m
ScreenMySaverPrefs_FRAMEWORKS = UIKit
ScreenMySaverPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
ScreenMySaverPrefs_INSTALL_PATH = /Library/PreferenceBundles
ScreenMySaverPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/ScreenMySaverPrefs.plist$(ECHO_END)
