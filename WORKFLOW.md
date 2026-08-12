# AppDataManager + IPAInstallerPro — Developer Workflow

## Overview

This repository contains **two** independent tools:

| Tool | Path | Status | Version |
|------|------|--------|---------|
| **AppData Manager** | `AppDataManager/` | ✅ Stable | 1.4.0 |
| **IPA Installer Pro** | `IPAInstallerPro/` | 🔄 Active Dev | 1.1.0 |

Both share the same repository but are **separate packages** in Sileo.

---

## Dual Repository System

| Repository | URL | Purpose | Update Method |
|------------|-----|---------|---------------|
| **Production** | `https://aosaid3224-ops.github.io/repo/` | Public releases | Manual only |
| **Development** | `https://aosaid3224-ops.github.io/repo-dev/` | Testing & beta | Automatic via CI/CD |

> **End users** see only AppData Manager in the production repo.
> **Developers** add the dev repo to Sileo to see and test IPA Installer Pro.

---

## IPA Installer Pro v1.1.0 — Architecture

### Core Philosophy
> **Precision > Speed** | **Evidence > Assumption** | **Verification > Exit Code** | **Root Cause > Patch**

### Installation Pipeline (11 Phases)

```
[IPA_OPEN] → [IPA_EXTRACT] → [APP_IDENTIFY] → [FILE_COPY] → [PERMISSION_chmod]
     → [PERMISSION_chown] → [SIGN_signAllAt] → [SIGN_signExe] → [FRAMEWORK]
     → [UICACHE] → [VERIFY] → [CLEANUP] → [COMPLETE]
```

### Zero-Gap Verification System

Every phase performs **deep verification** before proceeding:

| Phase | Verification Checks |
|-------|---------------------|
| **FILE_COPY** | File count match, size match, symlink preservation, deep copy verification via `copyfile()` |
| **PERMISSION_chmod** | `stat()` mode bits ≥ 755 |
| **PERMISSION_chown** | `stat()` uid=0 (root), gid=0 (wheel) |
| **SIGN_signAllAt** | `ldid -d` signature detection |
| **SIGN_signExe** | File exists + readable + signed |
| **FRAMEWORK** | Per-dylib: `stat()` mode/uid/gid + `access(X_OK)` + `ldid -d` |
| **VERIFY** | `access(X_OK)` on executable + `otool -L` dependency resolution + LSApplicationWorkspace registration |

### Live Installation Logging

Real-time structured logging with:
- **Timestamped entries** (HH:mm:ss.SSS)
- **Phase indicators** (visual dots in UI)
- **Structured verification** (PASS/FAIL with detail)
- **Command execution tracking** (exit codes + output)
- **File operation tracking** (path + result + errno)
- **Stat results** (mode, uid, gid)
- **Access checks** (R_OK, W_OK, X_OK, F_OK)

### Provider Selection (Fallback Chain)

```
1. Direct Install (score: 100) — preferred
   └─ Deep verification + live logging
2. appinst (score: 100) — fallback
3. System Install (score: 10) — last resort
```

If the primary provider fails, the engine automatically tries the next provider.

---

## File Structure

```
IPAInstallerPro/
├── Core/
│   ├── DirectInstallationProvider.m    ← Main provider (zero-gap verification)
│   ├── SystemInstallationProvider.m    ← LSApplicationWorkspace fallback
│   ├── AppInstInstallationProvider.m   ← appinst CLI fallback
│   ├── InstallationEngine.m            ← Provider orchestrator
│   ├── LiveInstallationLogger.h/m      ← Real-time logging system
│   ├── IPAValidator.m                  ← IPA integrity checks
│   ├── IPAExtractor.m                  ← Metadata extraction
│   ├── CapabilityManager.m             ← Environment detection
│   ├── RootlessManager.m               ← Rootless path resolution
│   ├── CrashReporter.m                 ← Crash log collection
│   ├── DiagnosticPipeline.m            ← System diagnostics
│   ├── ProcessMonitor.m                ← Process monitoring
│   ├── LogCollector.m                  ← Log aggregation
│   └── TransactionLogger.m             ← Operation journaling
├── UI/
│   ├── MainViewController.m            ← IPA file browser
│   ├── IPAFileBrowserViewController.m  ← File picker
│   ├── IPAInstallViewController.m      ← Install confirmation
│   ├── InstallationProgressViewController.m ← Live log viewer
│   └── SettingsViewController.m        ← Preferences
├── helper.c                            ← setuid root helper
├── entitlements.plist                  ← Wide entitlements
├── Makefile                            ← Build configuration
└── control                             ← Package metadata
```

---

## Development Workflow

### 1. Make Changes
Edit source files in `IPAInstallerPro/`.

### 2. Bump Version
Update `IPAInstallerPro/control`:
```
Version: X.Y.Z
```

### 3. Commit & Push
```bash
git add .
git commit -m "feat: description"
git push origin main
```

### 4. Automatic CI/CD
- `.github/workflows/sync-to-repo.yml` triggers on push
- Builds the package
- Generates `Packages` and `Release`
- Pushes to `repo-dev/` branch

### 5. Test in Sileo
Add `https://aosaid3224-ops.github.io/repo-dev/` to Sileo.
Refresh sources. Install/update IPA Installer Pro.

### 6. Promote to Production
When stable, run the manual release workflow:
- `.github/workflows/release-to-production.yml`
- This copies from `repo-dev/` to `repo/`

---

## Testing Checklist

Before any release, verify:

- [ ] Build succeeds (`make clean && make`)
- [ ] Package installs without errors
- [ ] Live log displays correctly
- [ ] All 11 phases complete with `verified=YES`
- [ ] `access(X_OK)` passes on executable
- [ ] `otool -L` shows all dependencies resolved
- [ ] App appears on SpringBoard after `uicache`
- [ ] App launches without crash
- [ ] Log can be copied/saved
- [ ] Works on Dopamine 3.x rootless

---

## Security Notes

- **Never commit GitHub tokens** to the repository
- **Never share Personal Access Tokens** in chat or issues
- Helper binary (`ipainstallerpro_helper`) runs as root via setuid
- Always verify entitlements before signing

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-11 | Initial release |
| 1.0.32 | 2026-08-12 | Operation logging, transaction system |
| **1.1.0** | **2026-08-13** | **Live logging, zero-gap verification, deep copy checks, stat() verification, access(X_OK), otool -L, fallback chain** |
