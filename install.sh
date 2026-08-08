#!/bin/bash
# =============================================================================
# AppData Manager - Direct Install Script for Jailbroken iOS
# =============================================================================
# Usage (on iPhone via SSH): ./install.sh
# =============================================================================

set -e

echo "=========================================="
echo "  📱 AppData Manager - Direct Install"
echo "  Dopamine 3.0 / Rootless"
echo "=========================================="

# التحقق من صلاحيات Root
if [ $(id -u) -ne 0 ]; then
    echo "❌ This script must be run as root!"
    echo "   Run: sudo ./install.sh"
    exit 1
fi

# التحقق من وجود الـ .deb
DEB_FILE=$(ls -t packages/*.deb 2>/dev/null | head -1)

if [ -z "$DEB_FILE" ]; then
    echo "❌ No .deb file found in packages/ directory!"
    echo "   Please build first with: ./build.sh"
    exit 1
fi

echo "📦 Found package: $(basename $DEB_FILE)"
echo "🔧 Installing..."

dpkg -i "$DEB_FILE"

# حل أي مشاكل تبعيات
if [ $? -ne 0 ]; then
    echo "⚠️ Fixing dependencies..."
    apt-get install -f -y
fi

# تحديث uicache
echo "🔄 Updating icon cache..."
uicache -p /var/jb/Applications/AppDataManager.app 2>/dev/null || uicache -p /Applications/AppDataManager.app 2>/dev/null || uicache 2>/dev/null || true

echo ""
echo "=========================================="
echo "  ✅ Installation Complete!"
echo "=========================================="
echo "📲 Open 'AppData Manager' from home screen"
echo ""
