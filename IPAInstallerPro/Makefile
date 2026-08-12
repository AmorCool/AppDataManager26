# IPAInstallerPro Makefile
# Version: 1.1.0

TARGET := iphone:clang:latest:15.0
ARCHS := arm64

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = IPAInstallerPro

IPAInstallerPro_FILES =     AppDelegate.m     MainViewController.m     IPAFileBrowserViewController.m     IPAInstallViewController.m     InstallationProgressViewController.m     SettingsViewController.m     Core/DirectInstallationProvider.m     Core/SystemInstallationProvider.m     Core/AppInstInstallationProvider.m     Core/InstallationEngine.m     Core/IPAValidator.m     Core/IPAExtractor.m     Core/CapabilityManager.m     Core/RootlessManager.m     Core/CrashReporter.m     Core/DiagnosticPipeline.m     Core/ProcessMonitor.m     Core/LogCollector.m     Core/TransactionLogger.m     Core/LiveInstallationLogger.m

IPAInstallerPro_FRAMEWORKS = UIKit Foundation
IPAInstallerPro_PRIVATE_FRAMEWORKS = MobileCoreServices
IPAInstallerPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations
IPAInstallerPro_CODESIGN_FLAGS = -Sentitlements.plist

include $(THEOS_MAKE_PATH)/application.mk

# Helper binary
TOOL_NAME = ipainstallerpro_helper

ipainstallerpro_helper_FILES = helper.c
ipainstallerpro_helper_CFLAGS = -fobjc-arc
ipainstallerpro_helper_CODESIGN_FLAGS = -Sentitlements.plist
ipainstallerpro_helper_INSTALL_PATH = /usr/bin

include $(THEOS_MAKE_PATH)/tool.mk
