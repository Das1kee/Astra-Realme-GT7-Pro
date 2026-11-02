import os
import re
import sys
import zipfile

ROOT = r"D:\DSH\Astra"
SRC = os.path.join(ROOT, "src")


def version():
    with open(os.path.join(SRC, "module.prop"), encoding="utf-8") as f:
        for line in f:
            if line.startswith("version="):
                return line.split("=", 1)[1].strip()
    return "0"


def build():
    v = version()
    out = os.path.join(ROOT, f"Astra-{v}.zip")
    if os.path.exists(out):
        os.remove(out)
    count = 0
    with zipfile.ZipFile(out, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for root, dirs, files in os.walk(SRC):
            dirs[:] = sorted(d for d in dirs if d not in (".git", "__pycache__", ".idea", ".vscode"))
            for name in sorted(files):
                if name.endswith((".pyc", ".zip")):
                    continue
                full = os.path.join(root, name)
                rel = os.path.relpath(full, SRC).replace("\\", "/")
                z.write(full, rel)
                count += 1
    print(f"built {out}: {count} entries, {os.path.getsize(out)} bytes")
    return out


if __name__ == "__main__":
    build()
