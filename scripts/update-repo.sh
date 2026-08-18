#!/bin/bash
# =============================================================================
# Update Repository — Generates Packages/Release and validates
# =============================================================================
# Usage: ./scripts/update-repo.sh [repo|repo-dev]
# =============================================================================

set -e

REPO_TYPE="${1:-repo-dev}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)/$REPO_TYPE"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "=========================================="
echo " 🔄 Updating Repository: $REPO_TYPE"
echo "=========================================="

if [ ! -d "$REPO_DIR" ]; then
    echo "❌ Repository directory not found: $REPO_DIR"
    exit 1
fi

# التحقق من وجود .deb files
POOL_DIR="$REPO_DIR/pool/main/iphoneos-arm64"
if [ ! -d "$POOL_DIR" ]; then
    echo "⚠️  Pool directory not found: $POOL_DIR"
    echo "   Creating..."
    mkdir -p "$POOL_DIR"
fi

DEB_COUNT=$(find "$POOL_DIR" -name "*.deb" | wc -l)
echo " 📦 Found $DEB_COUNT .deb package(s)"

if [ "$DEB_COUNT" -eq 0 ]; then
    echo "⚠️  No packages to index!"
    echo "   Build packages first with: ./build.sh"
    exit 1
fi

# توليد Packages و Release
if [ "$REPO_TYPE" = "repo-dev" ]; then
    python3 "$SCRIPT_DIR/generate-repo.py" "$REPO_DIR" --dev
else
    python3 "$SCRIPT_DIR/generate-repo.py" "$REPO_DIR" --prod
fi

# التحقق
python3 "$SCRIPT_DIR/validate-repo.py" "$REPO_DIR"

echo ""
echo "=========================================="
echo " ✅ Repository $REPO_TYPE updated!"
echo "=========================================="
echo ""
echo " 📋 Next steps:"
echo "    1. git add $REPO_TYPE/"
echo "    2. git commit -m 'Update $REPO_TYPE packages'"
echo "    3. git push origin main"
echo ""
echo " 🌐 URL: https://aosaid3224-ops.github.io/$REPO_TYPE/"
