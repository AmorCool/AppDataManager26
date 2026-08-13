# AppDataManager + IPAInstallerPro — Root Makefile
# Usage: make [all|appdatamanager|ipainstallerpro|repo|repo-dev|clean]

.PHONY: all appdatamanager ipainstallerpro repo repo-dev clean install test

all: appdatamanager ipainstallerpro repo repo-dev

appdatamanager:
	@echo "🔨 Building AppData Manager..."
	$(MAKE) -C AppDataManager package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
	@mkdir -p repo/pool/main/iphoneos-arm64/
	@cp AppDataManager/packages/*.deb repo/pool/main/iphoneos-arm64/ 2>/dev/null || true

ipainstallerpro:
	@echo "🔨 Building IPA Installer Pro..."
	$(MAKE) -C IPAInstallerPro package THEOS_PACKAGE_SCHEME=rootless FINALPACKAGE=1
	@mkdir -p repo-dev/pool/main/iphoneos-arm64/
	@cp IPAInstallerPro/packages/*.deb repo-dev/pool/main/iphoneos-arm64/ 2>/dev/null || true

repo:
	@echo "📝 Generating production repo..."
	@python3 scripts/generate-repo.py repo --prod
	@python3 scripts/validate-repo.py repo

repo-dev:
	@echo "📝 Generating dev repo..."
	@python3 scripts/generate-repo.py repo-dev --dev
	@python3 scripts/validate-repo.py repo-dev

clean:
	@echo "🧹 Cleaning..."
	$(MAKE) -C AppDataManager clean 2>/dev/null || true
	$(MAKE) -C IPAInstallerPro clean 2>/dev/null || true

install:
	@echo "📱 Installing latest packages to device..."
	@./build.sh all

test:
	@echo "🧪 Running validation tests..."
	@python3 scripts/validate-repo.py repo-dev
