# 🗑 AppData Manager

**Professional App Data Management Tool for iOS Jailbreak**

[![iOS](https://img.shields.io/badge/iOS-15.0%2B-blue)](https://developer.apple.com/ios/)
[![Jailbreak](https://img.shields.io/badge/Jailbreak-Rootless-green)](https://github.com/opa334/Dopamine)
[![Dopamine](https://img.shields.io/badge/Dopamine-3.0-purple)](https://ellekit.space/dopamine/)
[![Architecture](https://img.shields.io/badge/Arch-arm64%20arm64e-orange)](https://developer.apple.com/documentation/xcode/building_a_universal_mac_binary_with_xcode)
[![License](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

---

## ✨ Features

- 📱 **List All Apps** — View all installed applications with real-time data sizes
- 🗑 **Wipe App Data** — Permanently delete app data (Documents, Library, Caches)
- 🛡 **System App Protection** — Prevents accidental wiping of critical system apps
- 📦 **Backup & Restore** — Create backups before wiping and restore anytime
- 🔍 **Search** — Quickly find apps by name or bundle ID
- 🌙 **Dark Mode** — Full support for iOS Dark Mode
- 📊 **Data Size** — Real-time calculation of app data sizes
- ⚡ **Rootless Compatible** — Works with Dopamine 3.0 and all rootless jailbreaks
- 🍎 **iOS 18 Support** — Fully compatible with iOS 18.3.1

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

### Direct Download

Visit: [aosaid3224-ops.github.io/repo](https://aosaid3224-ops.github.io/repo/)

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

### Quick Build

```bash
# Clone the repository
git clone https://github.com/aosaid3224-ops/AppDataManager.git
cd AppDataManager

# Build for Dopamine 3.0 / Rootless
./build.sh
```

### Manual Build

```bash
make clean
make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
```

The `.deb` file will be in the `packages/` directory.

---

## 📋 Compatibility

| Jailbreak | iOS Version | Device | Status |
|-----------|-------------|--------|--------|
| **Dopamine 3.0** | iOS 15.0 - 18.7.1 | A8 - A17, M1-M2 | ✅ Fully Supported |
| Dopamine 2.x | iOS 15.0 - 16.6.1 | A8 - A16 | ✅ Supported |
| Palera1n | iOS 15.0 - 17.x | A8 - A11 | ✅ Supported |
| XinaA15 | iOS 15.0 - 15.4.1 | A12+ | ⚠️ Untested |

---

## ⚠️ Important Notes

- **This app runs unsandboxed** with root privileges
- **System apps are protected** — wipe action is disabled for critical system apps
- **Always backup before wiping** — data deletion is permanent
- **Use at your own risk**

---

## 🏗 Project Structure

```
AppDataManager/
├── Makefile                          # Theos build configuration
├── control                           # Package metadata
├── entitlements.plist                # Sandbox bypass entitlements
├── build.sh                          # Automated build script
├── install.sh                        # Direct install script
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

- [opa334](https://github.com/opa334) — Dopamine Jailbreak & libroot
- [Theos](https://theos.dev) — Build system
- [ElleKit](https://ellekit.space) — Tweak injection

---

## 📄 License

This project is licensed under the MIT License.

---

**Made with ❤️ by aosaid3224**


<!-- Build trigger: 2026-08-08 -->

<!-- CI trigger: production pipeline v1 -->

<!-- CI trigger: fix broken pipe v2 -->

<!-- CI trigger: fix validation v3 -->

<!-- CI trigger: PAT secret added, Pages enabled -->

<!-- CI trigger: v5 production pipeline with GITHUB_TOKEN and gh-pages validation -->
