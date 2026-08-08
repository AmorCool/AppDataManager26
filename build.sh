#!/bin/bash
# =============================================================================
# AppData Manager - Build Script for Dopamine 3.0 / Rootless Jailbreak
# =============================================================================
# Usage: ./build.sh
# Requirements: Theos installed, iOS SDK, Xcode Command Line Tools
# =============================================================================

set -e

echo "=========================================="
echo "  📱 AppData Manager Build Script"
echo "  Dopamine 3.0 / Rootless Compatible"
echo "=========================================="
echo ""

# التحقق من Theos
if [ -z "$THEOS" ]; then
    echo "❌ ERROR: THEOS environment variable not set!"
    echo "   Please install Theos: https://theos.dev/docs/installation"
    exit 1
fi

echo "✅ THEOS found at: $THEOS"

# تنظيف
make clean

# بناء للـ Rootless (Dopamine 3.0)
echo ""
echo "🔨 Building for Rootless Jailbreak..."
echo "   Architecture: iphoneos-arm64"
echo "   Target: iOS 15.0+"
echo ""

make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

# التحقق من نجاح البناء
DEB_FILE=$(ls -t packages/*.deb 2>/dev/null | head -1)

if [ -f "$DEB_FILE" ]; then
    echo ""
    echo "✅ Build Successful!"
    echo "📦 Package: $DEB_FILE"
    echo ""

    # عرض معلومات الحزمة
    echo "📋 Package Info:"
    dpkg-deb -I "$DEB_FILE" | grep -E "Package:|Version:|Architecture:|Depends:"
    echo ""

    # تثبيت يدوي (اختياري)
    read -p "🚀 Install via SSH? (y/n): " choice
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        read -p "📱 Enter iPhone IP: " iphone_ip
        echo "📤 Transferring to device..."
        scp "$DEB_FILE" root@$iphone_ip:/tmp/
        echo "🔧 Installing..."
        ssh root@$iphone_ip "dpkg -i /tmp/$(basename $DEB_FILE) && uicache -p /var/jb/Applications/AppDataManager.app || uicache -p /Applications/AppDataManager.app"
        echo "✅ Installed!"
    fi

    # نسخ للـ Repo (اختياري)
    read -p "📦 Copy to repo? (y/n): " repo_choice
    if [ "$repo_choice" = "y" ] || [ "$repo_choice" = "Y" ]; then
        REPO_PATH="../repo/pool/main/iphoneos-arm64/"
        mkdir -p "$REPO_PATH"
        cp "$DEB_FILE" "$REPO_PATH"
        echo "✅ Copied to repo!"
        echo ""
        echo "📝 Next steps for repo:"
        echo "   1. cd ../repo"
        echo "   2. ./update_repo.sh"
        echo "   3. git add . && git commit -m 'Update package' && git push"
    fi
else
    echo "❌ Build failed!"
    exit 1
fi

echo ""
echo "=========================================="
echo "  🎉 Done!"
echo "=========================================="
