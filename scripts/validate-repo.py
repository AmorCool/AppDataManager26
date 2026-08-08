#!/usr/bin/env python3
"""
Validate APT/Sileo repository structure and content.
Exits with code 1 if any check fails.
"""

import os
import sys
import re


def fail(msg):
    print(f"  ❌ {msg}", file=sys.stderr)
    return False


def ok(msg):
    print(f"  ✅ {msg}")
    return True


def validate_repo(repo_root):
    errors = 0

    print("[validate-repo] Starting validation...")
    print()

    # 1. Check required files exist and are non-empty
    print("[validate-repo] Checking required files...")
    required_files = ['Packages', 'Packages.bz2', 'Packages.xz', 'Release']
    for fname in required_files:
        path = os.path.join(repo_root, fname)
        if not os.path.exists(path):
            errors += 1
            fail(f"Missing file: {fname}")
        elif os.path.getsize(path) == 0:
            errors += 1
            fail(f"Empty file: {fname}")
        else:
            ok(f"{fname} exists ({os.path.getsize(path)} bytes)")

    # 2. Check .deb exists in pool
    print()
    print("[validate-repo] Checking .deb package...")
    deb_dir = os.path.join(repo_root, 'pool', 'main', 'iphoneos-arm64')
    debs = []
    if os.path.isdir(deb_dir):
        debs = [f for f in os.listdir(deb_dir) if f.endswith('.deb')]

    if not debs:
        errors += 1
        fail(f"No .deb found in {deb_dir}")
    else:
        for d in debs:
            ok(f"Found .deb: {d}")

    # 3. Validate Packages content
    print()
    print("[validate-repo] Validating Packages format...")
    packages_path = os.path.join(repo_root, 'Packages')
    if os.path.exists(packages_path):
        with open(packages_path) as f:
            content = f.read()

        checks = [
            ('Package field', r'^Package:\s+\S+'),
            ('Version field', r'^Version:\s+\S+'),
            ('Architecture field', r'^Architecture:\s+iphoneos-arm64'),
            ('Maintainer field', r'^Maintainer:\s+\S+'),
            ('Filename field', r'^Filename:\s+pool/main/iphoneos-arm64/'),
            ('Size field', r'^Size:\s+[1-9]\d*'),
            ('MD5sum field', r'^MD5sum:\s+[a-f0-9]{32}'),
            ('SHA256 field', r'^SHA256:\s+[a-f0-9]{64}'),
        ]

        for name, pattern in checks:
            if re.search(pattern, content, re.MULTILINE):
                ok(f"{name} valid")
            else:
                errors += 1
                fail(f"{name} missing or invalid")

        # Check for placeholders
        if 'Size: 0' in content or 'Size: 0000' in content:
            errors += 1
            fail("Placeholder Size detected")
        if 'MD5sum: 00000000000000000000000000000000' in content:
            errors += 1
            fail("Placeholder MD5 detected")
        if 'SHA256: 0000000000000000000000000000000000000000000000000000000000000000' in content:
            errors += 1
            fail("Placeholder SHA256 detected")

    # 4. Validate Release file
    print()
    print("[validate-repo] Validating Release format...")
    release_path = os.path.join(repo_root, 'Release')
    if os.path.exists(release_path):
        with open(release_path) as f:
            rel_content = f.read()

        rel_checks = [
            ('Origin', 'Origin:'),
            ('Label', 'Label:'),
            ('Suite', 'Suite:'),
            ('Architectures', 'Architectures: iphoneos-arm64'),
            ('Components', 'Components: main'),
            ('MD5Sum section', 'MD5Sum:'),
            ('SHA256 section', 'SHA256:'),
        ]

        for name, text in rel_checks:
            if text in rel_content:
                ok(f"{name} present")
            else:
                errors += 1
                fail(f"{name} missing")

    # 5. Verify hashes match actual files
    print()
    print("[validate-repo] Verifying file hashes...")
    import hashlib

    if os.path.exists(packages_path) and os.path.exists(release_path):
        with open(release_path) as f:
            rel = f.read()

        # Extract MD5 for Packages from Release
        md5_match = re.search(r'^ ([a-f0-9]{32})\s+\d+\s+Packages$', rel, re.MULTILINE)
        if md5_match:
            expected_md5 = md5_match.group(1)
            actual_md5 = hashlib.md5(open(packages_path, 'rb').read()).hexdigest()
            if expected_md5 == actual_md5:
                ok(f"Packages MD5 matches Release ({actual_md5})")
            else:
                errors += 1
                fail(f"Packages MD5 mismatch: expected {expected_md5}, got {actual_md5}")

        # Extract SHA256 for Packages from Release
        sha256_match = re.search(r'^ ([a-f0-9]{64})\s+\d+\s+Packages$', rel, re.MULTILINE)
        if sha256_match:
            expected_sha = sha256_match.group(1)
            actual_sha = hashlib.sha256(open(packages_path, 'rb').read()).hexdigest()
            if expected_sha == actual_sha:
                ok(f"Packages SHA256 matches Release ({actual_sha})")
            else:
                errors += 1
                fail(f"Packages SHA256 mismatch: expected {expected_sha}, got {actual_sha}")

    # Summary
    print()
    print("=" * 50)
    if errors == 0:
        print("✅ VALIDATION PASSED — Repository is Sileo-ready!")
        print(f"   Found {len(debs)} package(s)")
        return 0
    else:
        print(f"❌ VALIDATION FAILED — {errors} error(s) found")
        return 1


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <repo-root>", file=sys.stderr)
        sys.exit(1)

    sys.exit(validate_repo(sys.argv[1]))
