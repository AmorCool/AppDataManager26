# 🗑 AppData Manager

**Professional App Data Management Tool for iOS Jailbreak**

[![iOS](https://img.shields.io/badge/iOS-15.0%2B-blue)](https://developer.apple.com/ios/)
[![Jailbreak](https://img.shields.io/badge/Jailbreak-Rootless-green)](https://github.com/opa334/Dopamine)
[![Architecture](https://img.shields.io/badge/Arch-arm64%20arm64e-orange)](https://developer.apple.com/documentation/xcode/building_a_universal_mac_binary_with_xcode)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ Features

- 📱 **List All Apps** — View all installed applications with data sizes
- 🗑 **Wipe App Data** — Permanently delete app data (Documents, Library, Caches)
- 📦 **Backup & Restore** — Create backups before wiping and restore anytime
- 🔍 **Search** — Quickly find apps by name or bundle ID
- 🌙 **Dark Mode** — Full support for iOS Dark Mode
- 📊 **Data Size** — Real-time calculation of app data sizes
- ⚡ **Rootless Compatible** — Works with Dopamine 3.0 and all rootless jailbreaks
- 🛡 **Safe** — Confirmation dialogs for destructive actions

---

## 📸 Screenshots

| Main Screen | App Actions | Backup Manager |
|-------------|-------------|----------------|
| List of all apps with sizes | Backup / Wipe / Restore options | View and manage all backups |

---

## 🚀 Installation

### Via Sileo (Recommended)

1. Add this repository to Sileo:
   ```
   https://aosaid3224-ops.github.io/repo/
   ```

2. Search for **"AppData Manager"**
3. Tap **Install**

### Manual Installation

```bash
# Build the package
make clean
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

# Install via SSH
scp packages/com.aosaid.appdatamgr_1.0.0_iphoneos-arm64.deb root@<your-iphone-ip>:/tmp/
ssh root@<your-iphone-ip>
dpkg -i /tmp/com.aosaid.appdatamgr_1.0.0_iphoneos-arm64.deb
uicache -p /var/jb/Applications/AppDataManager.app
```

---

## 🛠 Building from Source

### Requirements

- [Theos](https://theos.dev/docs/installation) installed
- iOS 15.0+ SDK
- Xcode Command Line Tools

### Build Steps

```bash
# Clone the repository
git clone https://github.com/aosaid3224-ops/AppDataManager.git
cd AppDataManager

# Build for rootless jailbreak
make clean
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

# The .deb file will be in the packages/ directory
```

---

## 📋 Compatibility

| Jailbreak | iOS Version | Status |
|-----------|-------------|--------|
| Dopamine 3.0 | iOS 15.0 - 18.7.1 | ✅ Fully Supported |
| Dopamine 2.x | iOS 15.0 - 16.6.1 | ✅ Supported |
| Palera1n | iOS 15.0 - 17.x | ✅ Supported |
| XinaA15 | iOS 15.0 - 15.4.1 | ⚠️ Untested |
| Checkra1n | iOS 12.0 - 14.8.1 | ❌ Not Supported (Rootful) |

---

## ⚠️ Important Notes

- **This app runs unsandboxed** with root privileges
- **Always backup before wiping** — data deletion is permanent
- **Do NOT wipe system apps** (SpringBoard, Settings, etc.) — may cause bootloops
- **Use at your own risk**

---

## 🏗 Project Structure

```
AppDataManager/
├── Makefile                          # Theos build configuration
├── control                           # Package metadata
├── entitlements.plist                # Sandbox bypass entitlements
├── main.m                            # Entry point
├── AppDelegate.h/m                   # App delegate
├── ViewController.h/m                # Main app list UI
├── AppDataManager.h/m                # Core data management logic
├── BackupManagerViewController.h/m   # Backup management UI
├── Resources/
│   └── Info.plist                    # App info
├── layout/DEBIAN/
│   ├── postinst                      # Post-install script
│   └── prerm                         # Pre-remove script
└── README.md                         # This file
```

---

## 🙏 Credits

- [opa334](https://github.com/opa334) — Dopamine Jailbreak
- [Theos](https://theos.dev) — Build system
- [libroot](https://github.com/opa334/libroot) — Rootless compatibility

---

## 📄 License

This project is licensed under the MIT License.

---

**Made with ❤️ by aosaid3224**
