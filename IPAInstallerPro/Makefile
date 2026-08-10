export TARGET = iphone:clang:latest:15.0
export ARCHS = arm64 arm64e

THEOS_PACKAGE_SCHEME = rootless
INSTALL_TARGET_PROCESSES = IPAInstallerPro

include $(THEOS)/makefiles/common.mk

APPLICATION_NAME = IPAInstallerPro

IPAInstallerPro_FILES = \
 main.m \
 AppDelegate.m \
 Core/Logger.m \
 Core/JailbreakEnvironment.m \
 Core/RootlessManager.m \
 Core/CapabilityManager.m \
 Core/IPAValidator.m \
 Core/IPAExtractor.m \
 Core/InstallationProvider.m \
 Core/AppInstInstallationProvider.m \
 Core/SystemInstallationProvider.m \
 Core/DirectInstallationProvider.m \
 Core/InstallationEngine.m \
 Core/VerificationEngine.m \
 Core/ApplicationManager.m \
 Core/DependencyManager.m \
 UI/MainViewController.m \
 UI/IPAFileBrowserViewController.m \
 UI/IPAInstallViewController.m \
 UI/InstallationProgressViewController.m \
 UI/InstalledAppsViewController.m \
 UI/AppDetailsViewController.m \
 UI/SettingsViewController.m

IPAInstallerPro_FRAMEWORKS = UIKit CoreGraphics
IPAInstallerPro_PRIVATE_FRAMEWORKS = MobileCoreServices
IPAInstallerPro_CFLAGS = -fobjc-arc -Wno-deprecated-declarations -Wno-unused-variable -Wno-format
IPAInstallerPro_CODESIGN_FLAGS = -Sentitlements.plist
IPAInstallerPro_RESOURCE_DIRS = Resources

include $(THEOS_MAKE_PATH)/application.mk

# Dopamine 3.0 / Rootless specific
after-install::
	install.exec "uicache -p /var/jb/Applications/IPAInstallerPro.app || uicache -p /Applications/IPAInstallerPro.app || true"

# Force xz compression
export THEOS_PLATFORM_DEB_COMPRESSION_TYPE = xz
