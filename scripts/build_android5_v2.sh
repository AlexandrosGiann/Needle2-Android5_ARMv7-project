#!/usr/bin/env bash
set -euo pipefail

# Needle 2 / Lenovo A2020A40 / Android 5.x ARMv7
#
# v2 fixes two issues seen with the official ARMv7 static archive:
#   1) libneedle.a was built with an NDK 30 generation libc++ and references
#      std::__ndk1::__hash_memory.  Therefore use NDK r30 for the final link.
#   2) the archive directly references the API-23+ stderr symbol.  Android
#      5.x uses __sF[] instead, so android5_compat.c supplies a bridge.
#
# The final executable is still targeted at API 21 and linked with:
#   --hash-style=both
# so Android 5.1 gets the legacy DT_HASH it requires.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR="$ROOT/vendor"
BUILD="$ROOT/build-v2"
OUT="$ROOT/out-v2"

SRC="$ROOT/src/needle_android5_main.c"
COMPAT="$ROOT/src/android5_compat.c"

API="${ANDROID_API:-21}"
NEEDLE_REV="${NEEDLE_REV:-main}"
BASE="https://huggingface.co/Cactus-Compute/needle2/resolve/${NEEDLE_REV}"

mkdir -p "$VENDOR" "$BUILD" "$OUT"

if [[ ! -f "$SRC" ]]; then
    echo "ERROR: missing $SRC" >&2
    echo "Expected repository layout: src/needle_android5_main.c" >&2
    exit 1
fi

if [[ ! -f "$COMPAT" ]]; then
    echo "ERROR: missing $COMPAT" >&2
    exit 1
fi

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

find_ndk30() {
    local candidates=()
    local p

    [[ -n "${ANDROID_NDK_HOME:-}" ]] && candidates+=("$ANDROID_NDK_HOME")
    [[ -n "${ANDROID_NDK_ROOT:-}" ]] && candidates+=("$ANDROID_NDK_ROOT")

    candidates+=(
        "$HOME/Downloads/android-ndk-r30"
        "$HOME/Android/Sdk/ndk/30.0.16248370"
    )

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

    for p in "${candidates[@]}"; do
        [[ -z "$p" ]] && continue
        [[ ! -f "$p/source.properties" ]] && continue
        rev="$(sed -n 's/^Pkg.Revision *= *//p' "$p/source.properties" | head -n1)"
        major="${rev%%.*}"
        if [[ "$major" =~ ^[0-9]+$ ]] && (( major >= 30 )); then
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

echo "========== NEEDLE 2 ANDROID-5 ARMv7 BUILD v2 =========="
echo "Android target API : $API"
echo "Needle revision    : $NEEDLE_REV"
echo

fetch "$BASE/android-armv7/libneedle.a?download=true" "$VENDOR/libneedle.a"
fetch "$BASE/android-armv7/needle.h?download=true"    "$VENDOR/needle.h"
fetch "$BASE/needle2.cact?download=true"              "$VENDOR/needle2.cact"

NDK="$(find_ndk30 || true)"
if [[ -z "$NDK" ]]; then
    cat >&2 <<'EOF'
ERROR: NDK r30 (or newer) not found.

The official libneedle.a was built with an NDK 30-generation libc++.
NDK r27 is too old for its std::__ndk1::__hash_memory reference.

Install Android NDK r30, then set for example:

  export ANDROID_NDK_HOME="$HOME/Downloads/android-ndk-r30"

and rerun:

  ./build_android5_v2.sh
EOF
    exit 2
fi

TAG="$(host_tag)"
TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$TAG"
CC="$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang"
CXX="$TOOLCHAIN/bin/armv7a-linux-androideabi${API}-clang++"
NM="$TOOLCHAIN/bin/llvm-nm"
READELF="$TOOLCHAIN/bin/llvm-readelf"

if [[ ! -x "$CC" || ! -x "$CXX" ]]; then
    echo "ERROR: ARMv7 API${API} clang wrappers not found in $TOOLCHAIN/bin" >&2
    exit 3
fi

echo "NDK                 : $NDK"
echo "NDK revision        : $(sed -n 's/^Pkg.Revision *= *//p' "$NDK/source.properties" | head -n1)"
echo "CC                  : $CC"
echo "CXX                 : $CXX"
echo

if [[ -x "$NM" ]]; then
    echo "========== PRELINK SYMBOL CHECK =========="
    echo "-- libneedle unresolved compatibility symbols --"
    "$NM" -u "$VENDOR/libneedle.a" 2>/dev/null | \
        grep -E '(^|[[:space:]])(stderr|stdin|stdout)$|__hash_memory' | \
        sort -u || true

    LIBCXX_STATIC="$TOOLCHAIN/sysroot/usr/lib/arm-linux-androideabi/libc++_static.a"
    if [[ -f "$LIBCXX_STATIC" ]]; then
        echo
        echo "-- NDK r30 libc++ provider check --"
        "$NM" -g "$LIBCXX_STATIC" 2>/dev/null | grep '__hash_memory' | head || true
    fi
    echo
fi

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

echo "========== COMPILE ANDROID-5 COMPAT =========="
"$CC" \
    -std=c11 \
    -O2 \
    -fPIE \
    -c "$COMPAT" \
    -o "$BUILD/android5_compat.o"

echo "========== LINK =========="
set +e
"$CXX" \
    -fPIE -pie \
    "$BUILD/needle_android5_main.o" \
    "$BUILD/android5_compat.o" \
    "$VENDOR/libneedle.a" \
    -Wl,--hash-style=both \
    -Wl,--pack-dyn-relocs=none \
    -Wl,-z,max-page-size=4096 \
    -Wl,--gc-sections \
    -static-libstdc++ \
    -pthread \
    -lm -ldl -llog -latomic \
    -o "$OUT/needle-android5.bin"
link_rc=$?
set -e

if (( link_rc != 0 )); then
    cat >&2 <<'EOF'

========== LINK FAILED ==========
Do not change anything yet.

Send the complete output starting at:
  ========== PRELINK SYMBOL CHECK ==========
through the linker error.

Any remaining undefined symbols now identify the next Android-5 compatibility
gap in the official prebuilt libneedle.a.
EOF
    exit "$link_rc"
fi

chmod +x "$OUT/needle-android5.bin"

echo
echo "========== ELF VERIFY =========="
file "$OUT/needle-android5.bin" || true

if [[ -x "$READELF" ]]; then
    "$READELF" -h "$OUT/needle-android5.bin" | \
        grep -E 'Class:|Data:|Machine:|Type:' || true

    echo
    HASHES="$("$READELF" -d "$OUT/needle-android5.bin" 2>/dev/null | grep -E '\((HASH|GNU_HASH)\)' || true)"
    printf '%s\n' "$HASHES"

    if ! grep -q '(HASH)' <<<"$HASHES"; then
        echo "ERROR: final executable does not contain legacy DT_HASH." >&2
        exit 4
    fi

    echo
    echo "-- Android 5 forbidden/newer stdio symbols still imported? --"
    "$READELF" -Ws "$OUT/needle-android5.bin" 2>/dev/null | \
        grep -E 'UND.*(stderr|stdin|stdout)$' || true
fi

cp -f "$VENDOR/needle2.cact" "$OUT/needle2.cact"

cp -f "$ROOT/examples/tools.json" "$OUT/tools.json"
cp -f "$ROOT/scripts/needle_android5_phone_test.py" "$OUT/needle_android5_phone_test.py"
cp -f "$ROOT/scripts/needle_android5_infer_test.py" "$OUT/needle_android5_infer_test.py"
cp -f "$ROOT/web/index.html" "$OUT/index.html"

if command -v sha256sum >/dev/null 2>&1; then
    (
        cd "$OUT"
        sha256sum needle-android5.bin needle2.cact tools.json > SHA256SUMS.txt
    )
fi

echo
echo "========== SUCCESS =========="
echo "PASS: linked with NDK r30-generation libc++"
echo "PASS: Android-5 stdio compatibility shim included"
echo "PASS: legacy DT_HASH present"
echo
ls -lh "$OUT"
echo
echo "Next:"
echo "  cd \"$OUT\""
echo "  python3 -m http.server 8000 --bind 0.0.0.0"
