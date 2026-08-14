THEOS_PACKAGE_SCHEME = rootless
TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AppDataManager

AppDataManager_FILES = main.m AppDelegate.m AppDataManager.m MainViewController.m AppDetailViewController.m BackupManagerViewController.m SettingsViewController.m
AppDataManager_FRAMEWORKS = UIKit Foundation CoreGraphics
AppDataManager_PRIVATE_FRAMEWORKS = MobileCoreServices
AppDataManager_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable
AppDataManager_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
