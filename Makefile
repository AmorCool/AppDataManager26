THEOS_DEVICE_IP = localhost
THEOS_DEVICE_PORT = 2222

export ARCHS = arm64
export TARGET = iphone:clang:16.5:15.0
export THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AppDataManager

AppDataManager_FILES = main.m AppDelegate.m AppDataManager.m MainViewController.m AppDetailViewController.m BackupManagerViewController.m SettingsViewController.m
AppDataManager_FRAMEWORKS = UIKit Foundation CoreGraphics
AppDataManager_PRIVATE_FRAMEWORKS = MobileCoreServices
AppDataManager_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AppDataManager_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# Rootless compatibility
after-package::
	@echo "✅ Rootless package built successfully"
