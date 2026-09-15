import os
import shutil
import subprocess
import time

PRIVATE_DIR = "/data/data/com.hipipal.qpy3/files/needle2-v2"

SEARCH_DIRS = [
    "/storage/emulated/0/Needle",
    "/sdcard/Needle",
    "/storage/emulated/0/Download",
    "/sdcard/Download",
]

BIN_NAMES = [
    "needle-android5.bin",
    "needle-android5",
]

def find_first(names):
    for d in SEARCH_DIRS:
        for name in names:
            p = os.path.join(d, name)
            if os.path.isfile(p):
                return p
    return None

def find_one(name):
    return find_first([name])

print("=== Needle 2 FIRST INFERENCE test ===")
print()

src_bin = find_first(BIN_NAMES)
src_model = find_one("needle2.cact")
src_tools = find_one("tools.json")

print("Binary:", src_bin)
print("Model :", src_model)
print("Tools :", src_tools)

if not src_bin or not src_model or not src_tools:
    print()
    print("ERROR: missing one or more files.")
    print("Expected:")
    print("  needle-android5.bin")
    print("  needle2.cact")
    print("  tools.json")
    raise SystemExit(1)

if not os.path.isdir(PRIVATE_DIR):
    os.makedirs(PRIVATE_DIR)

dst_bin = os.path.join(PRIVATE_DIR, "needle-android5.bin")
dst_model = os.path.join(PRIVATE_DIR, "needle2.cact")
dst_tools = os.path.join(PRIVATE_DIR, "tools.json")

print()
print("Copying to private QPython directory...")
shutil.copyfile(src_bin, dst_bin)
shutil.copyfile(src_model, dst_model)
shutil.copyfile(src_tools, dst_tools)
os.chmod(dst_bin, 0o755)

print("Executable:", os.access(dst_bin, os.X_OK))
print("Binary size:", os.path.getsize(dst_bin))
print("Model size :", os.path.getsize(dst_model))
print("Tools size :", os.path.getsize(dst_tools))

prompt = "turn the light on"

cmd = [
    dst_bin,
    "--model", dst_model,
    "--tools", dst_tools,
    "--prompt", prompt,
    "--max-tokens", "64",
]

print()
print("===== COMMAND =====")
print(" ".join(cmd))
print()
print("Prompt:", prompt)
print()
print("===== RUNNING INFERENCE =====")

t0 = time.time()

try:
    p = subprocess.Popen(
        cmd,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        cwd=PRIVATE_DIR,
    )
    out, _ = p.communicate()
    dt = time.time() - t0

    print("Return code:", p.returncode)
    print("Elapsed: %.3f s" % dt)
    print()
    print("===== OUTPUT =====")
    try:
        print(out.decode("utf-8", "replace"))
    except Exception:
        print(repr(out))

except Exception as e:
    print("EXEC ERROR:", repr(e))
