import os
import shutil
import subprocess
import hashlib

PRIVATE_DIR = "/data/data/com.hipipal.qpy3/files/needle2-v2"

SEARCH_DIRS = [
    "/storage/emulated/0/Needle",
    "/sdcard/Needle",
    "/storage/emulated/0/Download",
    "/sdcard/Download",
]

BIN_NAMES = ["needle-android5.bin", "needle-android5"]

def find_file(name):
    for d in SEARCH_DIRS:
        p = os.path.join(d, name)
        if os.path.isfile(p):
            return p
    return None

def find_binary():
    for d in SEARCH_DIRS:
        for name in BIN_NAMES:
            p = os.path.join(d, name)
            if os.path.isfile(p):
                return p
    return None

def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        while True:
            b = f.read(1024 * 1024)
            if not b:
                break
            h.update(b)
    return h.hexdigest()

print("=== Needle 2 Android 5 phone test ===")
print()

FILES = {
    "binary": find_binary(),
    "needle2.cact": find_file("needle2.cact"),
    "tools.json": find_file("tools.json"),
}

for name in FILES:
    print("%s: %s" % (name, FILES[name]))

missing = [k for k, v in FILES.items() if not v]
if missing:
    print()
    print("MISSING:", ", ".join(missing))
    print("Searched:")
    for d in SEARCH_DIRS:
        print("  ", d)
    raise SystemExit(1)

if not os.path.isdir(PRIVATE_DIR):
    os.makedirs(PRIVATE_DIR)

print()
print("Private dir:", PRIVATE_DIR)
print("Writable:", os.access(PRIVATE_DIR, os.W_OK))

dst_bin = os.path.join(PRIVATE_DIR, "needle-android5.bin")
dst_model = os.path.join(PRIVATE_DIR, "needle2.cact")
dst_tools = os.path.join(PRIVATE_DIR, "tools.json")

print()
print("Copying files...")
shutil.copyfile(FILES["binary"], dst_bin)
shutil.copyfile(FILES["needle2.cact"], dst_model)
shutil.copyfile(FILES["tools.json"], dst_tools)
os.chmod(dst_bin, 0o755)

print("Binary size:", os.path.getsize(dst_bin))
print("Model size :", os.path.getsize(dst_model))
print("Tools size :", os.path.getsize(dst_tools))
print("Executable :", os.access(dst_bin, os.X_OK))

print()
print("Binary SHA256:")
print(sha256(dst_bin))
print()
print("Model SHA256:")
print(sha256(dst_model))

print()
print("===== RUNNING --help =====")
try:
    p = subprocess.Popen(
        [dst_bin, "--help"],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=PRIVATE_DIR,
    )
    out, _ = p.communicate()
    print("Return code:", p.returncode)
    print()
    try:
        print(out.decode("utf-8", "replace"))
    except Exception:
        print(repr(out))
except Exception as e:
    print("EXEC ERROR:", repr(e))
