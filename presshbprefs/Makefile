TARGET := iphone:clang:latest:15.0
THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

BUNDLE_NAME = PressHBPrefs

PressHBPrefs_FILES = PressHBRootListController.m
PressHBPrefs_FRAMEWORKS = UIKit
PressHBPrefs_LDFLAGS = -Wl,-undefined,dynamic_lookup
PressHBPrefs_INSTALL_PATH = /Library/PreferenceBundles
PressHBPrefs_CFLAGS = -fobjc-arc

include $(THEOS_MAKE_PATH)/bundle.mk

internal-stage::
	$(ECHO_NOTHING)mkdir -p $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences$(ECHO_END)
	$(ECHO_NOTHING)cp Entry.plist $(THEOS_STAGING_DIR)/Library/PreferenceLoader/Preferences/PressHBPrefs.plist$(ECHO_END)
