#!/usr/bin/env bash
# Build upstream and produce a relocatable tarball.
# Customize clone/configure/build/install; keep packaging layout stable.
set -euo pipefail

# version_env from package.toml (default EXAMPLE_VERSION) — set by create_releases
VERSION_RAW="${EXAMPLE_VERSION:-${PACKAGE_VERSION:?set EXAMPLE_VERSION or PACKAGE_VERSION}}"
BUILD_TARGET="${BUILD_TARGET:-linux-amd64}"
OUTPUT_DIR="${OUTPUT_DIR:-/out}"
UPSTREAM_REPO="${UPSTREAM_REPO:-https://github.com/example-org/example.git}"
PACKAGE_NAME="${PACKAGE_NAME:-example}"
JOBS="${JOBS:-$(nproc)}"
KEEP_SYMBOLS="${KEEP_SYMBOLS:-0}"
DISTRIBUTOR="${DISTRIBUTOR:-actions-precompiled}"

if [[ "$VERSION_RAW" =~ ^v ]]; then
  TAG="${VERSION_RAW#v}"
  NORMALIZED_TAG="$VERSION_RAW"
else
  TAG="$VERSION_RAW"
  NORMALIZED_TAG="$VERSION_RAW"
fi

case "$BUILD_TARGET" in
  linux-amd64|linux-x86_64) ARCHIVE_SUFFIX="linux-amd64" ;;
  linux-aarch64|linux-arm64) ARCHIVE_SUFFIX="linux-aarch64" ;;
  *)
    echo "Unsupported BUILD_TARGET: $BUILD_TARGET (linux-amd64, linux-aarch64)" >&2
    exit 1
    ;;
esac

WORKDIR="${WORKDIR:-/tmp/${PACKAGE_NAME}-build}"
SRC_DIR="${WORKDIR}/src"
BUILD_DIR="${WORKDIR}/build"
STAGE_DIR="${WORKDIR}/stage"
PREFIX_DIR="${STAGE_DIR}/${PACKAGE_NAME}"

rm -rf "$WORKDIR"
mkdir -p "$SRC_DIR" "$BUILD_DIR" "$PREFIX_DIR" "$OUTPUT_DIR"

echo "========================================="
echo "Building ${PACKAGE_NAME} ${VERSION_RAW}"
echo "  BUILD_TARGET:  ${BUILD_TARGET}"
echo "  ARCHIVE:       ${PACKAGE_NAME}-${TAG}-${ARCHIVE_SUFFIX}.tar.gz"
echo "========================================="

clone_tag() {
  local try_tag="$1"
  git clone --depth 1 --branch "$try_tag" "$UPSTREAM_REPO" "$SRC_DIR"
}

if ! clone_tag "$NORMALIZED_TAG" 2>/dev/null; then
  rm -rf "$SRC_DIR"
  mkdir -p "$SRC_DIR"
  if ! clone_tag "$TAG"; then
    echo "Failed to clone tag ${NORMALIZED_TAG} or ${TAG} from ${UPSTREAM_REPO}" >&2
    exit 1
  fi
fi

# --- YOUR BUILD HERE ---
# Example CMake project. Replace with autotools/meson/cargo/… as needed.
cmake -G Ninja -S "$SRC_DIR" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/usr \
  -DCMAKE_INSTALL_RPATH='\$ORIGIN/../lib' \
  -DCMAKE_BUILD_RPATH_USE_ORIGIN=ON

cmake --build "$BUILD_DIR" --parallel "$JOBS"
DESTDIR="$PREFIX_DIR" cmake --install "$BUILD_DIR"

# Flatten DESTDIR/usr → package root
if [[ -d "$PREFIX_DIR/usr" ]]; then
  shopt -s dotglob nullglob
  for entry in "$PREFIX_DIR"/usr/*; do
    base="$(basename "$entry")"
    if [[ -e "$PREFIX_DIR/$base" ]]; then
      cp -a "$entry"/. "$PREFIX_DIR/$base"/ 2>/dev/null || mv "$entry"/* "$PREFIX_DIR/$base"/
    else
      mv "$entry" "$PREFIX_DIR/$base"
    fi
  done
  shopt -u dotglob nullglob
  rm -rf "$PREFIX_DIR/usr"
fi

mkdir -p "$PREFIX_DIR/bin" "$PREFIX_DIR/lib"

# If install put a binary elsewhere, fix paths here.
# Real binary + wrapper pattern (optional):
#   mv "$PREFIX_DIR/bin/${PACKAGE_NAME}" "$PREFIX_DIR/bin/${PACKAGE_NAME}.bin"
#   write wrapper that sets LD_LIBRARY_PATH=$ROOT/lib

# Bundle non-system shared libs (minimal helper)
is_system_lib() {
  case "$1" in
    /lib/*|/lib64/*|/usr/lib/*|/usr/lib64/*) return 0 ;;
    *) return 1 ;;
  esac
}

declare -A SEEN_LIBS=()
copy_lib() {
  local src="$1"
  [[ -z "$src" || ! -e "$src" ]] && return 0
  local real
  real="$(readlink -f "$src")"
  [[ -z "$real" || ! -f "$real" ]] && return 0
  [[ -n "${SEEN_LIBS[$real]+x}" ]] && return 0
  SEEN_LIBS[$real]=1
  is_system_lib "$real" && return 0
  local base
  base="$(basename "$real")"
  case "$base" in ld-linux*.so*|ld-*.so) return 0 ;; esac
  echo "  bundling $real"
  cp -a "$real" "$PREFIX_DIR/lib/"
  while read -r dep; do
    [[ -z "$dep" ]] && continue
    copy_lib "$dep"
  done < <(ldd "$real" 2>/dev/null | awk '/=> \// { print $3 }' || true)
}

if [[ -x "$PREFIX_DIR/bin/${PACKAGE_NAME}" ]]; then
  while read -r dep; do
    copy_lib "$dep"
  done < <(ldd "$PREFIX_DIR/bin/${PACKAGE_NAME}" 2>/dev/null | awk '/=> \// { print $3 }' || true)
  # RPATH for direct binary
  if command -v patchelf >/dev/null; then
    patchelf --set-rpath '$ORIGIN/../lib' "$PREFIX_DIR/bin/${PACKAGE_NAME}" 2>/dev/null || true
  fi
fi

cat > "$PREFIX_DIR/BUILDINFO.txt" <<META
package=${PACKAGE_NAME}
version=${TAG}
upstream_tag=${NORMALIZED_TAG}
build_target=${BUILD_TARGET}
distributor=${DISTRIBUTOR}
built_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
META

if [[ ! -x "$PREFIX_DIR/bin/${PACKAGE_NAME}" ]]; then
  echo "Expected bin/${PACKAGE_NAME} after install — adjust build_and_package.sh" >&2
  find "$PREFIX_DIR" -type f | head -40 >&2
  exit 1
fi

# In-container smoke (loader)
if ! ldd "$PREFIX_DIR/bin/${PACKAGE_NAME}" | tee /tmp/ldd.txt | grep -q 'not found'; then
  echo "ldd: OK"
else
  echo "Unresolved libraries:" >&2
  grep 'not found' /tmp/ldd.txt >&2 || true
  exit 1
fi

ARCHIVE_NAME="${PACKAGE_NAME}-${TAG}-${ARCHIVE_SUFFIX}.tar.gz"
tar -czf "${OUTPUT_DIR}/${ARCHIVE_NAME}" -C "$STAGE_DIR" "${PACKAGE_NAME}"
echo "Done: ${OUTPUT_DIR}/${ARCHIVE_NAME}"
ls -lh "${OUTPUT_DIR}/${ARCHIVE_NAME}"
