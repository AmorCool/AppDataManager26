#!/usr/bin/env python3
"""
Generate APT/Sileo repository metadata from .deb packages in pool/.
Supports multiple packages. Reads checksums from the actual files in pool/
to guarantee they match what Git serves.

Usage:
    python3 generate-repo.py <repo-root>

The repo-root must contain:
    pool/main/iphoneos-arm64/*.deb

Produces:
    Packages, Packages.gz, Packages.bz2, Packages.xz, Release
"""

import os
import sys
import hashlib
import subprocess
import gzip
import bz2
import lzma


def run_cmd(cmd, check=True):
    result = subprocess.run(cmd, capture_output=True, text=True)
    if check and result.returncode != 0:
        print(f"ERROR: {' '.join(cmd)}\n{result.stderr}", file=sys.stderr)
        sys.exit(1)
    return result


def file_hash(filepath, algorithm):
    h = hashlib.new(algorithm)
    with open(filepath, 'rb') as f:
        while True:
            chunk = f.read(65536)
            if not chunk:
                break
            h.update(chunk)
    return h.hexdigest()


def file_size(filepath):
    return os.path.getsize(filepath)


def get_deb_control(deb_path):
    """Extract full control file from .deb using dpkg-deb -f"""
    result = run_cmd(['dpkg-deb', '-f', deb_path], check=True)
    return result.stdout.strip()


def generate_package_entry(deb_path, repo_root):
    """Generate a single Packages entry for one .deb file.
    Reads the file from pool/ to guarantee checksums match served bytes."""
    control = get_deb_control(deb_path)
    size = file_size(deb_path)
    md5 = file_hash(deb_path, 'md5')
    sha256 = file_hash(deb_path, 'sha256')

    deb_name = os.path.basename(deb_path)
    rel_path = f"pool/main/iphoneos-arm64/{deb_name}"

    entry = f"""{control}
Filename: {rel_path}
Size: {size}
MD5sum: {md5}
SHA256: {sha256}
"""
    return entry


def generate_packages(repo_root):
    """Generate Packages file from ALL .deb files in pool/."""
    pool_dir = os.path.join(repo_root, 'pool', 'main', 'iphoneos-arm64')
    if not os.path.isdir(pool_dir):
        print(f"ERROR: pool directory not found: {pool_dir}", file=sys.stderr)
        sys.exit(1)

    debs = sorted([f for f in os.listdir(pool_dir) if f.endswith('.deb')])
    if not debs:
        print(f"ERROR: No .deb files found in {pool_dir}", file=sys.stderr)
        sys.exit(1)

    entries = []
    for deb_name in debs:
        deb_path = os.path.join(pool_dir, deb_name)
        print(f"[generate-repo] Processing: {deb_name} ({file_size(deb_path)} bytes)")
        entry = generate_package_entry(deb_path, repo_root)
        entries.append(entry)

    packages_content = "\n".join(entries)

    packages_path = os.path.join(repo_root, 'Packages')
    with open(packages_path, 'w') as f:
        f.write(packages_content)

    # Compress
    with open(packages_path, 'rb') as src:
        data = src.read()

    with open(os.path.join(repo_root, 'Packages.gz'), 'wb') as f:
        f.write(gzip.compress(data))

    with open(os.path.join(repo_root, 'Packages.bz2'), 'wb') as f:
        f.write(bz2.compress(data))

    with open(os.path.join(repo_root, 'Packages.xz'), 'wb') as f:
        f.write(lzma.compress(data))

    print(f"[generate-repo] Packages generated ({len(debs)} package(s))")
    return packages_content


def generate_release(repo_root):
    """Generate Release file with MD5Sum and SHA256 sections."""
    files = [
        ('Packages', os.path.join(repo_root, 'Packages')),
        ('Packages.gz', os.path.join(repo_root, 'Packages.gz')),
        ('Packages.bz2', os.path.join(repo_root, 'Packages.bz2')),
        ('Packages.xz', os.path.join(repo_root, 'Packages.xz')),
    ]

    md5_lines = []
    sha256_lines = []

    for name, path in files:
        if os.path.exists(path):
            sz = file_size(path)
            md5 = file_hash(path, 'md5')
            sha256 = file_hash(path, 'sha256')
            md5_lines.append(f" {md5} {sz:>16} {name}")
            sha256_lines.append(f" {sha256} {sz:>16} {name}")

    md5_block = "\n".join(md5_lines) if md5_lines else ""
    sha256_block = "\n".join(sha256_lines) if sha256_lines else ""

    release_content = f"""Origin: aosaid3224 Repo
Label: aosaid3224
Suite: stable
Version: 1.0
Codename: ios
Architectures: iphoneos-arm64
Components: main
Description: aosaid3224 Official Repo - Dopamine 3.0 / Rootless Compatible
MD5Sum:
{md5_block}
SHA256:
{sha256_block}
"""

    release_path = os.path.join(repo_root, 'Release')
    with open(release_path, 'w') as f:
        f.write(release_content)

    print("[generate-repo] Release generated")
    return release_content


if __name__ == '__main__':
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} <repo-root>", file=sys.stderr)
        sys.exit(1)

    repo_root = sys.argv[1]

    if not os.path.isdir(repo_root):
        print(f"ERROR: repo-root is not a directory: {repo_root}", file=sys.stderr)
        sys.exit(1)

    # Ensure pool directory exists
    pool_dir = os.path.join(repo_root, 'pool', 'main', 'iphoneos-arm64')
    os.makedirs(pool_dir, exist_ok=True)

    # Generate metadata from files already in pool/
    generate_packages(repo_root)
    generate_release(repo_root)

    print("[generate-repo] Repository generation complete!")
