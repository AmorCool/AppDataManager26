TARGET := iphone:clang:latest:15.0
ARCHS = arm64 arm64e
INSTALL_TARGET_PROCESSES = AppDataManager

THEOS_PACKAGE_SCHEME = rootless

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = AppDataManager

AppDataManager_FILES = main.m AppDelegate.m ViewController.m AppDataManager.m BackupManagerViewController.m
AppDataManager_FRAMEWORKS = UIKit CoreGraphics
AppDataManager_PRIVATE_FRAMEWORKS = MobileCoreServices
AppDataManager_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
AppDataManager_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk
