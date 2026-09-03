#!/usr/bin/env bash
# Patch Flutter plugin Gradle files for Android Gradle Plugin 9.
#
# AGP 9 refuse getDefaultProguardFile('proguard-android.txt')
# (le fichier par défaut embarque -dontoptimize). Plusieurs plugins
# stables, notamment flutter_inappwebview_android 1.1.3, l'utilisent encore.
# On remplace par proguard-android-optimize.txt dans le pub-cache.
set -euo pipefail

python3 - <<'PY'
from pathlib import Path
import os

roots = []
pub = os.environ.get("PUB_CACHE")
if pub:
    roots.append(Path(pub))
roots.append(Path.home() / ".pub-cache")
# Flutter tool cache (au cas où un plugin y serait copié)
flutter_root = os.environ.get("FLUTTER_ROOT")
if flutter_root:
    roots.append(Path(flutter_root) / ".pub-cache")

old = "proguard-android.txt"
new = "proguard-android-optimize.txt"
patched = []
seen = set()

for root in roots:
    if not root.exists():
        continue
    for path in root.rglob("build.gradle*"):
        key = str(path.resolve()) if path.exists() else str(path)
        if key in seen:
            continue
        seen.add(key)
        try:
            text = path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if old not in text:
            continue
        path.write_text(text.replace(old, new), encoding="utf-8")
        patched.append(str(path))

if patched:
    print(f"Patched {len(patched)} Gradle file(s) for AGP 9 ProGuard:")
    for p in patched:
        print(f"  - {p}")
else:
    print("No plugin Gradle files still referencing proguard-android.txt.")
PY
