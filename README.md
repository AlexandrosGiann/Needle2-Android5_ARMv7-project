# Needle 2 on a Lenovo A2020A40 (Android 5.1 / ARMv7)

## Overview

This repository documents an experiment to run **Cactus Needle 2** on a very old **Lenovo A2020A40** running **Android 5.1**, **32-bit ARMv7**, with **QPython 3H** available on the device.

The original plan was to explore two extreme portability paths:

1. **Pure JavaScript in Firefox, without WebAssembly**
2. **Pure Python in QPython 3H, using only built-in/standard-library modules**

During the investigation, however, we found that Needle 2 already ships with an **Android ARMv7 native build**. That changed the strategy completely.

Instead of reimplementing the entire inference runtime in JavaScript or Python, we first tried to run the official ARMv7 engine directly on the phone.

The official ARMv7 executable did not start on Android 5.1 because of compatibility problems with the old Android dynamic linker. The solution was to use the official `libneedle.a`, relink it for **Android API 21**, add a small compatibility shim for the old Bionic stdio ABI, and produce a PIE executable containing the legacy **`DT_HASH`** table required by Android 5.x.

The final result was successful.

```text
Return code: 0
Elapsed: 2.843 s

needle_load rc=0
needle_init rc=42
needle_complete rc=15
```

The prompt:

```text
turn the light on
```

produced the correct structured tool call:

```json
{
  "type": "call",
  "success": true,
  "function_calls": [
    {
      "name": "set_light",
      "arguments": {
        "on": true
      }
    }
  ],
  "confidence": 1.0,
  "prefill_tps": 26.2,
  "decode_tps": 16.5,
  "peak_ram_mb": 32.4
}
```

So Needle 2 successfully performed native inference on **Android 5.1 / ARMv7 hardware roughly a decade old**.

---

## Hardware

### Lenovo A2020A40

The test device:

```text
Model: Lenovo A2020A40
OS: Android 5.1
Python-reported architecture: armv7l
CPU class: 32-bit ARMv7 / Cortex-A7 class
SoC: Qualcomm Snapdragon 210 class
RAM: 1 GB class
```

QPython reported:

```text
machine: armv7l
```

The important point is that this is a **32-bit ARM device**, not ARM64.

### Host laptop

The compatibility build was produced on a Linux laptop.

Example shell prompt:

```text
alex@alex-hp250g5notebookpc
```

The laptop was used only for:

- downloading upstream Needle 2 artifacts
- Android NDK cross-compilation and linking
- building the Android 5 compatibility executable
- serving files to the phone over the local network

The final inference test ran on the phone, not on the laptop.

---

## Software

### On the Lenovo

```text
Android: 5.1
QPython: QPython 3H
Python: 3.6.6
Architecture: armv7l
Browser: Firefox
```

The QPython executable was:

```text
/data/data/com.hipipal.qpy3/files/bin/python3-android5
```

QPython was used only as a:

- file launcher
- file copier
- `chmod` helper
- `subprocess` wrapper
- test harness
- benchmark timer

**QPython did not perform the model inference itself.**

Inference ran inside the native ARMv7 Needle engine.

### On the laptop

The build environment used:

```text
Linux
bash
curl
unzip
python3
Android NDK r27d
Android NDK r30
clang / clang++
lld
llvm-readelf
llvm-nm
```

**NDK r27d** was tried first, but rejected for the final link.

The successful final build used:

```text
Android NDK r30
Pkg.Revision = 30.0.16248370
```

---


# Quick Start From This Repository

This repository intentionally does **not** include the upstream model, static library, or prebuilt Needle executable.

After cloning or downloading the repository, place an Android NDK r30 installation on the host and run:

```bash
export ANDROID_NDK_HOME="$HOME/Downloads/android-ndk-r30"

chmod +x scripts/build_android5_v2.sh
./scripts/build_android5_v2.sh
```

The script downloads the required upstream artifacts and creates a deployment bundle under:

```text
out-v2/
```

including:

```text
needle-android5.bin
needle2.cact
tools.json
needle_android5_phone_test.py
needle_android5_infer_test.py
index.html
SHA256SUMS.txt
```

To serve that bundle to the phone over the LAN:

```bash
cd out-v2
python3 -m http.server 8000 --bind 0.0.0.0
```

Then open `http://<LAPTOP-IP>:8000/` in Firefox on the Lenovo.

---

# Original Goal

The project initially started as two independent portability experiments.

## Pure JavaScript

The first idea was:

```text
Firefox
  ↓
Pure JavaScript
  ↓
TypedArrays
  ↓
No WebAssembly
```

This followed the same general philosophy as an earlier experiment where MobileCLIP had been ported to pure JavaScript on old Android hardware.

## Pure Python

The second idea was:

```text
QPython 3H
  ↓
Python 3.6
  ↓
built-in / standard-library modules only
  ↓
no pip
```

`pip` was not usable in the target environment, so any pure-Python runtime would have needed to rely on modules such as:

```text
array
struct
math
json
memoryview
os
subprocess
```

---

# Why We Did Not Start With Pure JavaScript or Pure Python

During the investigation, we discovered official Needle 2 artifacts for:

```text
android-armv7
```

including:

```text
needle
libneedle.a
needle.h
```

That changed the priority.

If a native ARMv7 inference engine already exists, it makes much more sense to test it first instead of immediately reimplementing:

- tokenizer logic
- quantized kernels
- attention
- KV cache
- model parsing
- tool-call generation
- runtime memory management

in JavaScript or Python.

The pure-JS and pure-Python ideas were therefore **not rejected as impossible**.

They were simply **no longer the shortest path to a working Needle 2 deployment on this phone**.

---

# Transferring Files to the Phone

Files were transferred from the laptop to the Lenovo over the local network.

On the laptop:

```bash
python3 -m http.server 8000 --bind 0.0.0.0
```

Then Firefox on the Lenovo opened:

```text
http://<LAPTOP-IP>:8000/
```

A small custom `index.html` page provided separate download buttons for each file.

The phone stored the downloaded files in shared storage, for example:

```text
/storage/emulated/0/Needle/
```

---

# Why the Binary Was Not Executed Directly From Shared Storage

Android shared storage is not a reliable place from which to execute native binaries.

Instead, QPython copied the executable into its app-private directory:

```text
/data/data/com.hipipal.qpy3/files/
```

and then applied:

```python
os.chmod(binary, 0o755)
```

Execution was performed through:

```python
subprocess.Popen(...)
```

So QPython acted only as a launcher.

---

# First Test: Official ARMv7 Executable

The upstream Android ARMv7 `needle` executable was tested first.

Its ELF header showed:

```text
ELF magic OK: True
ELF class: 1
ELF endian: 1
ELF machine: 40
```

Meaning:

```text
32-bit
little-endian
ARM
```

This confirmed that:

- the CPU architecture matched
- the file was a valid ARM ELF executable
- QPython could copy it
- the app-private directory was writable
- executable permissions worked

However, execution failed.

The key error was:

```text
CANNOT LINK EXECUTABLE:
empty/missing DT_HASH
(built with --hash-style=gnu?)
```

---

# What the `DT_HASH` Error Meant

Android 5.1 uses an old dynamic linker.

The upstream executable contained newer ELF metadata based on:

```text
GNU_HASH
```

while the Android 5 linker still expected the legacy:

```text
DT_HASH
```

So the initial failure was **not** caused by:

- the wrong CPU
- the wrong ARM architecture
- insufficient RAM
- QPython
- executable permissions
- a corrupted binary

It was primarily a **dynamic linker compatibility problem**.

---

# Decision: Relink Instead of Rewrite

Because upstream also provides:

```text
libneedle.a
```

the next strategy became:

```text
official libneedle.a
        +
small custom main()
        +
Android NDK
        ↓
Android-5-compatible executable
```

This was dramatically simpler than reimplementing the full Needle inference runtime.

---

# First Custom Build

A wrapper was created:

```text
needle_android5_main.c
```

It used the public native API:

```c
needle_load(...)
needle_init(...)
needle_complete(...)
needle_reset()
```

The model was loaded separately from:

```text
needle2.cact
```

The first build targeted:

```text
ARMv7
Android API 21
PIE
```

with linker settings including:

```text
-fPIE
-pie
-Wl,--hash-style=both
-Wl,--pack-dyn-relocs=none
-Wl,-z,max-page-size=4096
```

The critical option was:

```text
--hash-style=both
```

so that the final ELF would contain both:

```text
GNU_HASH
DT_HASH
```

---

# Why NDK r27d Was Rejected

The first relink attempt with NDK r27d failed with two unresolved symbols.

## 1. `stderr`

The linker reported:

```text
undefined symbol: stderr
```

The upstream `libneedle.a` had been built against a newer Android/Bionic ABI where a symbol like:

```c
FILE *stderr
```

is directly available.

Android 5.x uses the older stdio ABI based on:

```text
__sF[]
```

## 2. `std::__ndk1::__hash_memory`

The second important failure was:

```text
undefined symbol:
std::__ndk1::__hash_memory(void const*, unsigned int)
```

Debug paths embedded in the upstream object files showed that the library had been built with a newer NDK/libc++ generation:

```text
.../ndk/30.0.14904198/...
```

So the link attempt effectively mixed:

```text
libneedle.a built with newer libc++
+
NDK r27 final C++ runtime
```

NDK r27 did not provide the expected implementation of that symbol.

### Decision

NDK r27 was **rejected for the final link**.

It was still perfectly capable of compiling ARMv7 code; the problem was C++ runtime compatibility with the prebuilt upstream archive.

---

# Android 5 stdio Compatibility Shim

A compatibility source file was created:

```text
android5_compat.c
```

For Android API levels below 23, it bridges the newer standard-stream symbol names to the old Bionic `__sF[]` array:

```c
extern FILE __sF[];

FILE *stdin  = &__sF[0];
FILE *stdout = &__sF[1];
FILE *stderr = &__sF[2];
```

This allowed the upstream library to resolve:

```text
stdin
stdout
stderr
```

while still running on the Android 5 Bionic ABI.

---

# Moving to NDK r30

Android NDK r30 was installed:

```text
Pkg.Revision = 30.0.16248370
```

A pre-link symbol check showed:

```text
libneedle unresolved:
    stderr
    std::__ndk1::__hash_memory
```

and NDK r30's libc++ did provide the required:

```text
std::__ndk1::__hash_memory
```

The final build therefore used:

```text
NDK r30 libc++
+
Android API 21 target
+
Android 5 stdio compatibility shim
+
--hash-style=both
```

---

# Successful Build

The final executable was produced as:

```text
needle-android5
```

and identified as:

```text
ELF 32-bit LSB pie executable
ARM
EABI5
SYSV
dynamically linked
interpreter /system/bin/linker
```

`llvm-readelf` showed:

```text
Class: ELF32
Data: little endian
Type: DYN
Machine: ARM
```

`Type: DYN` is expected for a PIE executable.

Most importantly, the dynamic section contained both:

```text
GNU_HASH
HASH
```

specifically:

```text
0x6ffffef5 (GNU_HASH)
0x00000004 (HASH)
```

The build verification completed with:

```text
PASS: linked with NDK r30-generation libc++
PASS: Android-5 stdio compatibility shim included
PASS: legacy DT_HASH present
```

---

# Renaming the Binary to `.bin`

On the phone, the executable was ultimately stored as:

```text
needle-android5.bin
```

The `.bin` extension does not change the file format.

It remains an ELF executable.

Executable permission is still required:

```text
chmod 755 needle-android5.bin
```

---

# First Successful Execution on the Lenovo

The first runtime test was:

```text
needle-android5.bin --help
```

Result:

```text
Return code: 0
```

and the wrapper printed:

```text
Needle 2 Android-5 ARMv7 wrapper
```

This proved that the entire startup chain now worked:

```text
Android 5 dynamic linker
        ↓
custom compatibility ELF
        ↓
libneedle
        ↓
main()
```

---

# Linker Warnings We Accepted

Android 5 still prints warnings such as:

```text
WARNING: linker: Unsupported flags DT_FLAGS_1=0x8000001
WARNING: linker: unused DT entry ...
```

These are caused by newer ELF dynamic tags that the Android 5 linker does not understand.

For now, these warnings are **accepted** because they are non-fatal.

The executable:

- loads successfully
- reaches `main()`
- runs `needle_load()`
- runs `needle_init()`
- runs `needle_complete()`
- produces correct structured output
- exits with process return code `0`

At this stage they are therefore treated as compatibility noise rather than a functional blocker.

---

# First Real Inference

The first full inference test used:

```text
needle_android5_infer_test.py
```

The script:

1. found the files in shared storage
2. copied them into QPython's app-private directory
3. applied executable permissions
4. started the native binary
5. measured total elapsed time

Approximate file sizes:

```text
needle-android5.bin: 18,352,092 bytes
needle2.cact:        13,737,807 bytes
tools.json:                 172 bytes
```

The command was equivalent to:

```bash
needle-android5.bin \
  --model needle2.cact \
  --tools tools.json \
  --prompt "turn the light on" \
  --max-tokens 64
```

---

# Test Tool Definition

The test used a single tool:

```json
[
  {
    "name": "set_light",
    "description": "Turn a light on or off",
    "parameters": {
      "type": "object",
      "properties": {
        "on": {
          "type": "boolean"
        }
      },
      "required": ["on"]
    }
  }
]
```

---

# Inference Result

The process returned:

```text
Return code: 0
Elapsed: 2.843 s
```

Internal wrapper output:

```text
needle_load rc=0
needle_init rc=42
needle_complete rc=15
```

The wrapper treated only negative values as errors.

The final result was:

```json
{
  "type": "call",
  "success": true,
  "error": null,
  "error_code": null,
  "reason": null,
  "function_calls": [
    {
      "name": "set_light",
      "arguments": {
        "on": true
      }
    }
  ],
  "reasoning": null,
  "confidence": 1.0,
  "prefill_tps": 26.2,
  "decode_tps": 16.5,
  "peak_ram_mb": 32.4,
  "validation": {
    "ungrounded": [],
    "negation": false
  }
}
```

So:

```text
turn the light on
```

was correctly converted into:

```text
set_light(on=true)
```

with:

```text
confidence = 1.0
```

---

# Measured Performance

The first end-to-end test reported:

| Metric | Result |
|---|---:|
| Total elapsed time | 2.843 s |
| Prefill throughput | 26.2 tokens/s |
| Decode throughput | 16.5 tokens/s |
| Peak RAM | 32.4 MB |

The measured `Elapsed` value includes more than steady-state inference:

- process startup
- model file loading
- `needle_load`
- `needle_init`
- inference
- output serialization
- process shutdown

So this is **not yet a warm-run or persistent-process benchmark**.

---

# What We Accepted

## Native ARMv7 inference

Accepted because an upstream native ARMv7 engine already existed and was proven to work.

## QPython only as a launcher

Accepted because:

- no `pip` is required
- only built-in Python modules are needed
- it can copy, chmod, and launch the native binary
- inference remains native

## Separate `needle2.cact`

Accepted for the compatibility wrapper through:

```c
needle_load(...)
```

## Android API 21 target

Accepted to maximize compatibility with Android 5.x.

## NDK r30 libc++

Accepted because it matches the C++ ABI expectations of the upstream `libneedle.a` much better than NDK r27.

## `--hash-style=both`

Required because Android 5 needs legacy:

```text
DT_HASH
```

## Android 5 stdio shim

Accepted because it resolves the ABI mismatch between:

```text
stderr
```

and:

```text
__sF[]
```

## Non-fatal linker warnings

Accepted temporarily because they do not prevent startup or inference.

---

# What We Rejected

## Running the upstream executable unchanged

Rejected for Android 5.1 because it failed with:

```text
missing DT_HASH
```

It was **not** rejected because it was ARMv7.

## NDK r27d for the final link

Rejected because it could not satisfy:

```text
std::__ndk1::__hash_memory
```

and also exposed the stdio ABI mismatch.

## Pure Python as the first implementation

Not pursued as the main inference path because it would require a full reimplementation of the Needle runtime.

It remains an interesting experiment, but native ARMv7 was the more direct route.

## Pure JavaScript as the first implementation

Also not pursued as the main path for the same reason.

A browser-only, no-WASM port remains technically interesting, but it is a separate portability project rather than the shortest path to a usable Needle 2 setup.

## Executing directly from shared storage

Not used as the final execution method.

The binary is copied into QPython's app-private directory before execution.

---

# What We Did Not Do

This project did **not**:

- reverse-engineer the model format
- rewrite the CQ kernels
- rewrite the tokenizer
- rewrite the attention engine
- implement pure-Python inference
- implement pure-JavaScript inference
- use WebAssembly
- root the phone
- build a custom Android APK
- build a JNI wrapper
- create an Android Studio project
- create a permanent background service
- connect Firefox to a persistent native HTTP server
- perform a multi-turn benchmark
- perform a thermal benchmark
- measure battery consumption
- perform long-context benchmarking
- build a broad correctness suite
- perform a full memory stress test

---

# What Still Needs Investigation

## 1. Persistent process

Right now each test starts a new process.

The next major step is:

```text
load model once
keep engine alive
serve many prompts
```

This should remove repeated startup and model initialization overhead.

## 2. Local HTTP server

The desired architecture is:

```text
native Needle process
        ↓
127.0.0.1:8080
        ↓
Firefox UI
```

Firefox would then be only the user interface, not the inference runtime.

## 3. Warm-run benchmark

We should measure separately:

```text
cold start
model load
tool indexing
prefill
decode
second prompt
third prompt
```

## 4. Memory behavior

We still need to measure:

- real process RSS
- peak RSS
- memory after repeated requests
- fragmentation
- model mapping behavior

## 5. Thermal throttling

The Snapdragon 210 is a very old SoC.

Repeated inference should be tested to see whether:

```text
decode_tps
```

drops as the device heats up.

## 6. Tool-call correctness

A larger validation suite should include:

```text
positive calls
negative calls
ambiguous prompts
multiple tools
multiple parameters
numbers
strings
booleans
nested objects
```

## 7. Linker warnings

Although harmless so far, it may be possible to remove additional unsupported ELF metadata and produce cleaner startup output on Android 5.

## 8. Binary size

The compatibility executable is around:

```text
18 MB
```

Possible future work:

```text
strip
LTO
gc-sections
symbol removal
```

without breaking Android 5 compatibility.

## 9. Pure JavaScript port

Still an interesting future project:

```text
Needle 2
→ Firefox
→ pure JavaScript
→ no WASM
```

This would be useful as a portability experiment independent of the native solution.

## 10. Pure Python port

Also still possible as a separate experiment:

```text
Needle 2
→ QPython 3H
→ Python 3.6
→ built-in libraries only
```

It is unlikely to match native speed, but it could be valuable as a reference or portability implementation.

---

# Suggested Repository Layout

```text
needle2-android5-armv7/
├── README.md
├── src/
│   ├── needle_android5_main.c
│   └── android5_compat.c
├── scripts/
│   ├── build_android5.sh
│   ├── build_android5_v2.sh
│   ├── needle_android5_phone_test.py
│   └── needle_android5_infer_test.py
├── web/
│   └── index.html
├── examples/
│   └── tools.json
└── docs/
    ├── logs/
    └── screenshots/
```

Upstream artifacts such as:

```text
libneedle.a
needle2.cact
needle
```

should **not automatically be committed to this repository** until their redistribution terms have been checked.

A safer repository design is to let the build script download them directly from the official upstream source.

---

# Reproduction Summary

In condensed form:

```text
1. Download upstream ARMv7 libneedle.a + needle.h + needle2.cact
2. Install Android NDK r30
3. Target armv7a-linux-androideabi21
4. Add Android 5 stdio compatibility shim
5. Link with --hash-style=both
6. Verify ELF32 / ARM / PIE / DT_HASH
7. Transfer files to the Lenovo over LAN
8. Copy executable into QPython private storage
9. chmod 755
10. Run --help
11. Run first inference
12. Confirm structured tool-call output
```

---

# Final Architecture

```text
                    Linux laptop
                         │
                         │ build / transfer
                         ▼
              Android-5 ARMv7 executable
                         │
               official libneedle.a
                         │
                  needle2.cact
                         │
                         ▼
                Lenovo A2020A40
                 Android 5.1
                    ARMv7
                         │
                 QPython launcher
                         │
                         ▼
                 Native inference
                         │
                         ▼
                 Structured JSON
```

---

# Project Status

```text
[✓] ARMv7 architecture confirmed
[✓] Official executable inspected
[✓] Android 5 linker incompatibility identified
[✓] DT_HASH issue solved
[✓] libc++ mismatch identified
[✓] NDK r30 compatibility solved
[✓] Android 5 stdio ABI shim implemented
[✓] ELF32 ARM PIE build successful
[✓] --help runs on Lenovo
[✓] needle_load succeeds
[✓] needle_init succeeds
[✓] needle_complete succeeds
[✓] Correct tool call produced
[✓] Peak RAM reported
[✓] Prefill/decode throughput reported
[ ] Persistent native server
[ ] Firefox UI
[ ] Warm-run benchmark
[ ] Multi-prompt validation
[ ] Thermal/battery testing
[ ] Pure JavaScript port
[ ] Pure Python port
```

---

# Key Takeaway

The main lesson from this experiment is that a compact modern AI runtime does not necessarily require modern Android hardware.

The Lenovo A2020A40 did not fail because it lacked enough RAM or because ARMv7 was inherently too old.

The initial blocker was mostly:

```text
toolchain / ABI / dynamic linker compatibility
```

Once the upstream ARMv7 static library was relinked with:

```text
Android API 21
NDK r30 libc++
legacy DT_HASH
Android 5 stdio shim
```

Needle 2 successfully performed inference and generated a correct structured tool call on Android 5.1.

This was exactly the kind of problem that was better solved at the compatibility layer than by rewriting the full model runtime.

---

## Disclaimer

This is experimental compatibility work on unsupported old Android hardware.

It is **not** an official Cactus build and should not be interpreted as an upstream-supported Android 5 configuration.

Needle, Cactus, model files, and upstream libraries remain the property of their respective authors.

Before redistributing upstream binaries or model artifacts publicly, verify their applicable license and redistribution terms.
