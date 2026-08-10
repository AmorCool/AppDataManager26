#!/usr/bin/env python3
import os, sys, hashlib, subprocess

REPO_DIR = sys.argv[1] if len(sys.argv) > 1 else "."
POOL_DIR = os.path.join(REPO_DIR, "pool", "main", "iphoneos-arm64")

def hash_file(path, algo):
    h = hashlib.new(algo)
    with open(path, "rb") as f:
        while chunk := f.read(8192):
            h.update(chunk)
    return h.hexdigest()

def get_deb_info(deb_path):
    try:
        out = subprocess.check_output(["dpkg-deb", "-f", deb_path], text=True)
        return out
    except:
        return ""

def main():
    packages = []
    if not os.path.exists(POOL_DIR):
        print(f"Pool dir not found: {POOL_DIR}")
        return

    for fname in sorted(os.listdir(POOL_DIR)):
        if not fname.endswith(".deb"):
            continue
        fpath = os.path.join(POOL_DIR, fname)
        size = os.path.getsize(fpath)
        md5 = hash_file(fpath, "md5")
        sha1 = hash_file(fpath, "sha1")
        sha256 = hash_file(fpath, "sha256")
        info = get_deb_info(fpath)

        entry = info.strip()
        entry += f"
Filename: pool/main/iphoneos-arm64/{fname}\n"
        entry += f"Size: {size}\n"
        entry += f"MD5sum: {md5}\n"
        entry += f"SHA1: {sha1}\n"
        entry += f"SHA256: {sha256}\n"
        packages.append(entry)

    packages_text = "\n".join(packages) + "\n"

    with open(os.path.join(REPO_DIR, "Packages"), "w") as f:
        f.write(packages_text)
    with open(os.path.join(REPO_DIR, "Packages.gz"), "wb") as f:
        import gzip
        f.write(gzip.compress(packages_text.encode()))
    with open(os.path.join(REPO_DIR, "Packages.bz2"), "wb") as f:
        import bz2
        f.write(bz2.compress(packages_text.encode()))
    with open(os.path.join(REPO_DIR, "Packages.xz"), "wb") as f:
        import lzma
        f.write(lzma.compress(packages_text.encode()))

    print(f"Generated Packages for {len(packages)} packages")

if __name__ == "__main__":
    main()
