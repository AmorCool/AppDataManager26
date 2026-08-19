# AppDataManager + IPAInstallerPro — Developer Workflow

## Overview

This repository contains **two** independent tools:

| Tool | Path | Status | Version |
|------|------|--------|---------|
| **AppData Manager** | repository root | ✅ Stable | 1.4.1 (v1.4.0 baseline) |
| **IPA Installer Pro** | `IPAInstallerPro/` | 🔄 Active Dev | 2.0.0 |

Both share the same repository but are **separate packages** in Sileo.

---

## Dual Repository System

| Repository | GitHub Repo | URL | Purpose |
|------------|-------------|-----|---------|
| **Production** | `aosaid3224-ops/repo` | `https://aosaid3224-ops.github.io/repo/` | Public releases |
| **Development** | `aosaid3224-ops/repo-dev` | `https://aosaid3224-ops.github.io/repo-dev/` | Testing & beta |

> **Note:** `repo/` and `repo-dev/` are **separate GitHub repositories**, NOT folders in this repo.
> CI/CD workflows push built packages to them automatically.

---

## CI/CD Workflows

### 1. Auto-Sync to Dev Repo (`.github/workflows/sync-to-repo.yml`)

**Triggers:**
- Automatically on every `push` to `main` that changes `IPAInstallerPro/**` or `scripts/**`
- Manually via `workflow_dispatch`

**What it does:**
1. Checks out this repo (source code)
2. Checks out `aosaid3224-ops/repo-dev` (separate repo)
3. Sets up Theos + dependencies on macOS runner
4. Builds IPA Installer Pro: `make clean && make package`
5. Copies `.deb` to `repo-dev/pool/main/iphoneos-arm64/`
6. Runs `scripts/generate-repo.py . --dev`
7. Commits and pushes `repo-dev`

**Requirements:**
- `secrets.PAT` must be set in repo Settings → Secrets → Actions
- PAT needs `repo` scope to push to `aosaid3224-ops/repo-dev`

### 2. Release to Production (`.github/workflows/release-to-production.yml`)

**Triggers:**
- Manual only (`workflow_dispatch`)

**What it does:**
1. Same build process as dev
2. Deploys to `aosaid3224-ops/repo` (production)
3. Requires typing `YES` to confirm

---

## Local Development Workflow

### Option A: Let CI/CD Handle Everything (Recommended)

```bash
# 1. Edit source files
# 2. Bump version in IPAInstallerPro/control
# 3. Commit and push
git add .
git commit -m "feat: description"
git push origin main

# 4. CI/CD automatically builds and deploys to repo-dev
# 5. Refresh Sileo to see the update
```

### Option B: Local Build (Advanced)

```bash
# Requires: macOS + Theos + dpkg + ldid
cd IPAInstallerPro
make clean
make package

# Manual deploy to local repo-dev folder for testing
cp packages/*.deb ../repo-dev/pool/main/iphoneos-arm64/
cd ../repo-dev
python3 ../scripts/generate-repo.py . --dev
```

---

## IPA Installer Pro v2.0.0 — Architecture

### Core Philosophy
> **Precision > Speed** | **Evidence > Assumption** | **Verification > Exit Code** | **Root Cause > Patch**

### Unified Provider Contract

Every installation provider MUST:
1. Accept `OperationLog` as parameter
2. Record every real operation to `OperationLog`
3. Return `InstallationResult` with evidence dictionary
4. Perform verification at each phase, not just check exit codes

### Provider Chain

```
1. Direct Install (priority: 100) — preferred
   └─ Root helper + ldid + deep verification
2. appinst (priority: 100) — fallback
3. System Install (priority: 10) — last resort
```

If primary fails, engine tries next automatically with full audit trail.

### OperationLog — Source of Truth

Every installation creates a transaction in `OperationLog`:
- Timestamped records for each phase
- Real file paths (not placeholders)
- Verification results (PASS/FAIL with detail)
- Evidence: stat results, access checks, signatures
- Transaction report accessible via UI

### Live Log Display

`InstallationProgressViewController` displays OperationLog in real-time:
- NSNotificationCenter broadcasts record updates
- UI receives updates without polling
- Each line shows: status icon + phase + operation + verification

---

## File Structure

```
IPAInstallerPro/
├── Core/
│   ├── DirectInstallationProvider.m    ← Main provider (zero-gap verification)
│   ├── SystemInstallationProvider.m    ← LSApplicationWorkspace fallback
│   ├── AppInstInstallationProvider.m   ← appinst CLI fallback
│   ├── InstallationEngine.m            ← Provider orchestrator + OperationLog integration
│   ├── InstallationProvider.h/m        ← Unified contract + Result with evidence
│   ├── OperationLog.m                  ← Transaction logging (source of truth)
│   ├── IPAValidator.m                  ← IPA integrity checks
│   ├── IPAExtractor.m                  ← Metadata extraction
│   ├── CapabilityManager.m             ← Environment detection
│   ├── RootlessManager.m               ← Rootless path resolution
│   ├── CrashReporter.m                 ← Crash log collection (separate from install)
│   ├── DiagnosticPipeline.m            ← System diagnostics (separate from install)
│   ├── ProcessMonitor.m                ← Process monitoring
│   ├── LogCollector.m                  ← Log aggregation
│   ├── TransactionLogger.m             ← Operation journaling
│   └── InstallationLogger.m            ← Legacy history logger
├── UI/
│   ├── MainViewController.m            ← IPA file browser
│   ├── IPAFileBrowserViewController.m  ← File picker
│   ├── IPAInstallViewController.m      ← Install confirmation
│   ├── InstallationProgressViewController.m ← Live OperationLog viewer
│   └── SettingsViewController.m        ← Environment info (no diagnostics)
├── helper.c                            ← setuid root helper
├── entitlements.plist                  ← Wide entitlements
├── Makefile                            ← Build configuration
└── control                             ← Package metadata
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | 2026-08-11 | Initial release |
| 1.0.32 | 2026-08-12 | Operation logging, transaction system |
| **2.0.0** | **2026-08-13** | **Architecture rewrite: unified provider contract, OperationLog integration, zero-gap verification, live log display, evidence-based results** |
| **1.4.1** | **2026-08-19** | **AppData Manager restored to the verified v1.4.0 baseline; package version bumped after restoration** |
| **1.7.18** | **2026-08-19** | **AppData Manager: use live filesystem statistics and never display unavailable containers as 0 B** |
| **1.7.17** | **2026-08-19** | **AppData Manager: preserve MCM container metadata ownership while normalizing restored app data** |
| **1.7.16** | **2026-08-19** | **AppData Manager: marshal container SPI to main, serialize Restore/Delete, improve errors, and make local builds AppData-only by default** |
| **1.7.15** | **2026-08-19** | **AppData Manager: exclude preserved MCM metadata from source/target content verification** |
| **1.7.14** | **2026-08-19** | **AppData Manager: normalize restored ownership, reject bundle/data UUID inference, and verify every restored relative file** |
| **1.7.13** | **2026-08-19** | **AppData Manager: fix NSError propagation from serialized Restore and preserve detailed verification failures** |
| **1.7.12** | **2026-08-19** | **AppData Manager: expose restore verification errors and refuse success without verified data recovery** |
| **1.7.11** | **2026-08-19** | **AppData Manager: enforce post-restore file/byte/path verification and preserve container metadata across delete and restore** |
| **1.7.10** | **2026-08-19** | **AppData Manager: verify restored files, bytes, standard directories, permissions, and rediscover the data container after deletion** |
| **1.7.9** | **2026-08-19** | **AppData Manager: fix Rootless user-data paths, unify backup directory with postinst, resolve data containers by metadata or bundle UUID, and verify every backup stage** |
| **1.7.8** | **2026-08-19** | **AppData Manager: require the primary container for backup success while treating unavailable App Group copies as optional** |
| **1.7.7** | **2026-08-19** | **AppData Manager: make complete container copies valid without a manifest and make secondary App Group failures non-fatal** |
| **1.7.6** | **2026-08-19** | **AppData Manager: trace the full restore flow, add backup manifests, and restore the primary container when group containers are unavailable** |
| **1.7.5** | **2026-08-19** | **AppData Manager: make restore container mapping resilient to regenerated UUIDs and validate all copy steps** |
| **1.7.4** | **2026-08-18** | **AppData Manager: remove LaunchServices/MCM private APIs from startup discovery and initial size statistics** |
| **1.7.3** | **2026-08-18** | **AppData Manager: perform LaunchServices discovery on the main thread only** |
| **1.7.2** | **2026-08-18** | **AppData Manager: defer LaunchServices discovery until the visible controller is ready** |
| **1.7.1** | **2026-08-18** | **AppData Manager: restore stable size scanning while retaining unified real statistics** |
| **1.7.0** | **2026-08-18** | **AppData Manager: stable size scanning, unified real statistics, and protected system-app handling** |
| **1.6.9** | **2026-08-18** | **AppData Manager: fixed UTF-8 byte-size generation for Release metadata** |
| **1.6.8** | **2026-08-18** | **AppData Manager: fixed absolute-path validation for multi-package Sileo deployment** |
| **1.6.7** | **2026-08-18** | **AppData Manager: multi-package repository validation and reliable Sileo dev deployment** |
| **1.6.6** | **2026-08-18** | **AppData Manager: unified backup-size calculation, sanitized backup matching, and reliable local build flow** |
| **1.6.5** | **2026-08-17** | **AppData Manager: consistent backups, cross-app restore protection, serialized backup deletion, and Sileo dev sync** |
