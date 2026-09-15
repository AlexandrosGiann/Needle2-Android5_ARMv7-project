#!/usr/bin/env bash
set -euo pipefail

# Build the official Needle 2 ARMv7 static library into an Android-5-compatible
# PIE executable. The important compatibility knobs are:
#   * target API 21 (Android 5.0; Lenovo Android 5.1 is API 22)
#   * --hash-style=both  -> emits old DT_HASH as well as GNU_HASH
#   * --pack-dyn-relocs=none
#   * 4096-byte max page size
#
# This script downloads the current official ARMv7 library/header/model unless
# those files already exist under ./vendor.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
BUILD="$ROOT/build"
OUT="$ROOT/out"
SRC="$ROOT/src/needle_android5_main.c"

API="${ANDROID_API:-21}"
NEEDLE_REV="${NEEDLE_REV:-main}"
BASE="https://huggingface.co/Cactus-Compute/needle2/resolve/${NEEDLE_REV}"

mkdir -p "$VENDOR" "$BUILD" "$OUT"

fetch() {
    local url="$1"
    local dst="$2"

    if [[ -s "$dst" ]]; then
        echo "[download] already present: $dst"
        return 0
    fi

    echo "[download] $url"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --retry-delay 2 -o "$dst.tmp" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -O "$dst.tmp" "$url"
    else
        echo "ERROR: install curl or wget." >&2
        exit 1
    fi
    mv "$dst.tmp" "$dst"
}

find_ndk() {
    local candidates=()
    local p

    [[ -n "${ANDROID_NDK_HOME:-}" ]] && candidates+=("$ANDROID_NDK_HOME")
    [[ -n "${ANDROID_NDK_ROOT:-}" ]] && candidates+=("$ANDROID_NDK_ROOT")

    if [[ -d "${ANDROID_SDK_ROOT:-}/ndk" ]]; then
        while IFS= read -r p; do candidates+=("$p"); done < <(
            find "$ANDROID_SDK_ROOT/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -Vr
        )
    fi

    if [[ -d "$HOME/Android/Sdk/ndk" ]]; then
        while IFS= read -r p; do candidates+=("$p"); done < <(
            find "$HOME/Android/Sdk/ndk" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort -Vr
        )
    fi

    candidates+=(
        "$HOME/Android/Sdk/ndk-bundle"
        "/opt/android-ndk"
        "/usr/lib/android-ndk"
    )

    for p in "${candidates[@]}"; do
        if [[ -n "$p" && -d "$p/toolchains/llvm/prebuilt" ]]; then
            printf '%s\n' "$p"
            return 0
        fi
    done
    return 1
}

host_tag() {
    case "$(uname -s)-$(uname -m)" in
        Linux-x86_64)  echo linux-x86_64 ;;
        Linux-aarch64) echo linux-aarch64 ;;
        Darwin-x86_64) echo darwin-x86_64 ;;
        Darwin-arm64)  echo darwin-x86_64 ;;
        *)
            echo "ERROR: unsupported build host: $(uname -s)-$(uname -m)" >&2
            return 1
            ;;
    esac
}

echo "========== NEEDLE 2 ANDROID-5 ARMv7 BUILD =========="
echo "Needle revision : $NEEDLE_REV"
echo "Android API     : $API"
echo

fetch "$BASE/android-armv7/libneedle.a?download=true" "$VENDOR/libneedle.a"
fetch "$BASE/android-armv7/needle.h?download=true"    "$VENDOR/needle.h"
fetch "$BASE/needle2.cact?download=true"              "$VENDOR/needle2.cact"

# Catch accidental Git-LFS pointer downloads early.
for f in "$VENDOR/libneedle.a" "$VENDOR/needle2.cact"; do
    size="$(wc -c < "$f")"
    if (( size < 1000000 )); then
        echo "ERROR: '$f' is unexpectedly small ($size bytes)." >&2
        echo "It may be a Git-LFS/Xet pointer instead of the real file." >&2
        rm -f "$f"
        exit 1
    fi
done

NDK="$(find_ndk || true)"
if [[ -z "$NDK" ]]; then
    cat >&2 <<'EOF'
ERROR: Android NDK not found.

Install an Android NDK on the laptop, then either:
  export ANDROID_NDK_HOME=/path/to/android-ndk
or install it under:
  ~/Android/Sdk/ndk/<version>/

NDK r25/r26/r27 are suitable for this experiment.
Then rerun:
  ./build_android5.sh
EOF
    exit 2
fi

TAG="$(host_tag)"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$TAG"
if [[ ! -d "$TOOLCHAIN" ]]; then
    echo "ERROR: NDK toolchain not found: $TOOLCHAIN" >&2
    exit 3
fi

CC="$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang"
CXX="$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang++"

if [[ ! -x "$CC" || ! -x "$CXX" ]]; then
    echo "ERROR: API-specific ARMv7 clang wrappers not found:" >&2
    echo "  $CC" >&2
    echo "  $CXX" >&2
    exit 4
fi

echo "NDK             : $NDK"
echo "CC              : $CC"
echo "CXX             : $CXX"
echo

echo "========== COMPILE WRAPPER =========="
"$CC" \
    -std=c11 \
    -O2 \
    -fPIE \
    -ffunction-sections \
    -fdata-sections \
    -I"$VENDOR" \
    -c "$SRC" \
    -o "$BUILD/needle_android5_main.o"

echo "========== LINK =========="
set +e
"$CXX" \
    -fPIE -pie \
    "$BUILD/needle_android5_main.o" \
    "$VENDOR/libneedle.a" \
    -Wl,--hash-style=both \
    -Wl,--pack-dyn-relocs=none \
    -Wl,-z,max-page-size=4096 \
    -Wl,--gc-sections \
    -static-libstdc++ \
    -pthread \
    -lm -ldl -llog -latomic \
    -o "$OUT/needle-android5"
link_rc=$?
set -e

if (( link_rc != 0 )); then
    cat >&2 <<'EOF'

========== LINK FAILED ==========
This is useful diagnostic information.

If the error names an undefined Android symbol, the prebuilt official
libneedle.a itself may require an API newer than Android 5.x.
Copy the complete linker output and send it back so we can identify the
exact symbol/API requirement.

If the error is about C++ runtime libraries instead, we can adjust only
the final linker command without touching Needle itself.
EOF
    exit "$link_rc"
fi

chmod +x "$OUT/needle-android5"

echo
echo "========== OUTPUT =========="
file "$OUT/needle-android5" || true
ls -lh "$OUT/needle-android5" "$VENDOR/needle2.cact"

READELF=""
for p in \
    "$TOOLCHAIN/bin/llvm-readelf" \
    "$(command -v readelf 2>/dev/null || true)"
do
    if [[ -n "$p" && -x "$p" ]]; then
        READELF="$p"
        break
    fi
done

if [[ -n "$READELF" ]]; then
    echo
    echo "========== ELF HEADER =========="
    "$READELF" -h "$OUT/needle-android5" | \
        grep -E 'Class:|Data:|Machine:|Type:' || true

    echo
    echo "========== DYNAMIC HASH TAGS =========="
    HASHES="$("$READELF" -d "$OUT/needle-android5" 2>/dev/null | grep -E '\((HASH|GNU_HASH)\)' || true)"
    printf '%s\n' "$HASHES"

    if ! grep -q '(HASH)' <<<"$HASHES"; then
        echo "ERROR: final binary has no old DT_HASH tag." >&2
        exit 5
    fi

    echo
    echo "PASS: legacy DT_HASH is present."
fi

echo
echo "========== PHONE BUNDLE =========="
cp -f "$VENDOR/needle2.cact" "$OUT/needle2.cact"

cat > "$OUT/tools.json" <<'EOF'
[
  {
    "name": "set_light",
    "description": "Turn a light on or off",
    "parameters": {
      "type": "object",
      "properties": {
        "on": { "type": "boolean" }
      },
      "required": ["on"]
    }
  }
]
EOF

if command -v sha256sum >/dev/null 2>&1; then
    (
        cd "$OUT"
        sha256sum needle-android5 needle2.cact tools.json > SHA256SUMS.txt
    )
fi

echo "Created:"
ls -lh "$OUT"

echo
echo "NEXT STEP:"
echo "  Serve the out/ directory on the LAN:"
echo
echo "    cd \"$OUT\""
echo "    python3 -m http.server 8000 --bind 0.0.0.0"
echo
echo "First test on the Lenovo should be --help only."
