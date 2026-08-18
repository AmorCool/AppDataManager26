#!/bin/bash
# =============================================================================
# AppDataManager + IPAInstallerPro — Unified Build Script
# Dopamine 3.0 / Rootless Compatible
# =============================================================================
# Usage: ./build.sh [all|appdatamanager|ipainstallerpro]
# =============================================================================

set -e

PROJECT_ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD_MODE="${1:-all}"

echo "=========================================="
echo " 📱 AppDataManager Build System"
echo " Mode: $BUILD_MODE"
echo "=========================================="
echo ""

# التحقق من Theos
if [ -z "$THEOS" ]; then
    echo "❌ ERROR: THEOS environment variable not set!"
    echo "   Install: https://theos.dev/docs/installation"
    exit 1
fi
echo "✅ THEOS: $THEOS"

# التحقق من الأدوات المطلوبة
for tool in dpkg-deb ldid uicache unzip; do
    if ! command -v "$tool" &> /dev/null; then
        echo "⚠️  Warning: $tool not found in PATH"
    fi
done
echo ""

BUILD_SUCCESS=0
BUILD_FAILED=0
BUILT_PACKAGES=()

# ========== بناء AppData Manager ==========
build_appdatamanager() {
    echo "=========================================="
    echo " 🔨 Building: AppData Manager"
    echo "=========================================="
    cd "$PROJECT_ROOT"

    make clean 2>/dev/null || true
    make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

    DEB=$(ls -t packages/*.deb 2>/dev/null | head -1)
    if [ -f "$DEB" ]; then
        echo "✅ AppData Manager built: $(basename $DEB)"
        BUILT_PACKAGES+=("$DEB")
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # نسخ إلى pool
        mkdir -p "$PROJECT_ROOT/repo/pool/main/iphoneos-arm64/"
        cp "$DEB" "$PROJECT_ROOT/repo/pool/main/iphoneos-arm64/"
        echo "   → Copied to repo/pool/"
    else
        echo "❌ AppData Manager build failed!"
        BUILD_FAILED=$((BUILD_FAILED + 1))
        return 1
    fi
    echo ""
}

# ========== بناء IPA Installer Pro ==========
build_ipainstallerpro() {
    echo "=========================================="
    echo " 🔨 Building: IPA Installer Pro"
    echo "=========================================="
    cd "$PROJECT_ROOT/IPAInstallerPro"

    make clean 2>/dev/null || true
    make package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1

    DEB=$(ls -t packages/*.deb 2>/dev/null | head -1)
    if [ -f "$DEB" ]; then
        echo "✅ IPA Installer Pro built: $(basename $DEB)"
        BUILT_PACKAGES+=("$DEB")
        BUILD_SUCCESS=$((BUILD_SUCCESS + 1))

        # نسخ إلى repo-dev فقط (للاختبار)
        mkdir -p "$PROJECT_ROOT/repo-dev/pool/main/iphoneos-arm64/"
        cp "$DEB" "$PROJECT_ROOT/repo-dev/pool/main/iphoneos-arm64/"
        echo "   → Copied to repo-dev/pool/"
    else
        echo "❌ IPA Installer Pro build failed!"
        BUILD_FAILED=$((BUILD_FAILED + 1))
        return 1
    fi
    echo ""
}

# ========== توليد repo ==========
generate_repo() {
    local repo_dir="$1"
    local is_dev="$2"

    echo "=========================================="
    echo " 📝 Generating repo: $(basename $repo_dir)"
    echo "=========================================="

    cd "$PROJECT_ROOT"

    if [ "$is_dev" = "true" ]; then
        python3 scripts/generate-repo.py "$repo_dir" --dev
    else
        python3 scripts/generate-repo.py "$repo_dir" --prod
    fi

    # التحقق
    python3 scripts/validate-repo.py "$repo_dir"
    echo ""
}

# ========== التثبيت الاختياري عبر SSH ==========
install_via_ssh() {
    local deb_path="$1"

    # Never block automated builds with an interactive prompt.
    if [ "${INSTALL_VIA_SSH:-0}" != "1" ]; then
        return 0
    fi

    read -p "📱 Install $(basename $deb_path) via SSH? (y/n): " choice
    if [ "$choice" = "y" ] || [ "$choice" = "Y" ]; then
        read -p "📱 iPhone IP: " iphone_ip
        echo "📤 Transferring..."
        scp "$deb_path" root@$iphone_ip:/tmp/
        echo "🔧 Installing..."
        ssh root@$iphone_ip "dpkg -i /tmp/$(basename $deb_path) && uicache -p /var/jb/Applications/*.app || uicache -p /Applications/*.app"
        echo "✅ Installed!"
    fi
}

# ========== التنفيذ الرئيسي ==========
case "$BUILD_MODE" in
    appdatamanager|adm)
        build_appdatamanager
        generate_repo "$PROJECT_ROOT/repo" "false"
        ;;
    ipainstallerpro|ipa)
        build_ipainstallerpro
        generate_repo "$PROJECT_ROOT/repo-dev" "true"
        ;;
    all|*)
        build_appdatamanager
        build_ipainstallerpro
        generate_repo "$PROJECT_ROOT/repo" "false"
        generate_repo "$PROJECT_ROOT/repo-dev" "true"
        ;;
esac

# ========== ملخص ==========
echo "=========================================="
echo " 📊 Build Summary"
echo "=========================================="
echo "  Success: $BUILD_SUCCESS"
echo "  Failed:  $BUILD_FAILED"
echo ""

if [ ${#BUILT_PACKAGES[@]} -gt 0 ]; then
    echo " 📦 Built packages:"
    for pkg in "${BUILT_PACKAGES[@]}"; do
        echo "    • $(basename $pkg)"
        dpkg-deb -I "$pkg" | grep -E "Package:|Version:|Architecture:" | sed 's/^/      /'
    done
    echo ""
fi

echo " 🌐 Repositories:"
echo "    Production: $PROJECT_ROOT/repo/"
echo "    Dev:        $PROJECT_ROOT/repo-dev/"
echo ""

if [ "$BUILD_FAILED" -gt 0 ]; then
    echo " ❌ Some builds failed!"
    exit 1
else
    echo " ✅ All builds successful!"

    # اقتراح التثبيت
    if [ ${#BUILT_PACKAGES[@]} -gt 0 ]; then
        echo ""
        last_index=$((${#BUILT_PACKAGES[@]} - 1))
        install_via_ssh "${BUILT_PACKAGES[$last_index]}"
    fi

    exit 0
fi
