#!/usr/bin/env bash
set -euo pipefail

# Build script for MuPDF shared library (Linux x64)
# Pinned strictly to version 1.24.10

VERSION="1.24.10"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
BUILD_DIR="${ROOT_DIR}/build/mupdf-src"
OUTPUT_DIR_X64="${ROOT_DIR}/native/prebuilt/linux/x64"
OUTPUT_DIR_X86_64="${ROOT_DIR}/native/prebuilt/linux/x86_64"
INCLUDE_DIR="${ROOT_DIR}/native/include"

echo "=== Building MuPDF v${VERSION} shared library ==="
mkdir -p "${BUILD_DIR}"
mkdir -p "${OUTPUT_DIR_X64}"
mkdir -p "${OUTPUT_DIR_X86_64}"
mkdir -p "${INCLUDE_DIR}"

TARBALL_URL="https://mupdf.com/downloads/archive/mupdf-${VERSION}-source.tar.gz"
SOURCE_DIR="${BUILD_DIR}/mupdf-${VERSION}-source"

if [ ! -d "${SOURCE_DIR}" ]; then
  echo "Downloading source tarball from ${TARBALL_URL}..."
  if curl -sSL --fail "${TARBALL_URL}" -o "${BUILD_DIR}/mupdf-${VERSION}-source.tar.gz"; then
    echo "Extracting tarball..."
    tar -xzf "${BUILD_DIR}/mupdf-${VERSION}-source.tar.gz" -C "${BUILD_DIR}"
  else
    echo "Tarball download failed, falling back to git clone..."
    git clone --depth 1 --branch "${VERSION}" --recurse-submodules https://github.com/ArtifexSoftware/mupdf.git "${SOURCE_DIR}"
  fi
fi

cd "${SOURCE_DIR}"

# Integrate Kawi exception-safe C bridge into Fitz
if [ -f "${ROOT_DIR}/native/src/mupdf_bridge.c" ]; then
  echo "Integrating Kawi C bridge..."
  cp -f "${ROOT_DIR}/native/src/mupdf_bridge.c" "source/fitz/mupdf_bridge.c"
fi

# Build shared library with release flags
echo "Compiling MuPDF shared library (release)..."
NPROC=$(nproc || echo 4)
make -j"${NPROC}" shared=yes build=release libs

# Locate the compiled shared library
SO_FILE=""
if [ -f "build/shared-release/libmupdf.so" ]; then
  SO_FILE="build/shared-release/libmupdf.so"
elif [ -f "build/shared-release/libmupdf.so.${VERSION}" ]; then
  SO_FILE="build/shared-release/libmupdf.so.${VERSION}"
elif compgen -G "build/shared-release/libmupdf.so*" > /dev/null; then
  SO_FILE=$(ls build/shared-release/libmupdf.so* | head -n 1)
fi

if [ -z "${SO_FILE}" ] || [ ! -f "${SO_FILE}" ]; then
  echo "Error: Could not find compiled libmupdf.so in build/shared-release/"
  exit 1
fi

echo "Found compiled library at: ${SO_FILE}"
cp -f "${SO_FILE}" "${OUTPUT_DIR_X64}/libmupdf.so"
cp -f "${SO_FILE}" "${OUTPUT_DIR_X86_64}/libmupdf.so"

# Also copy header files to native/include
echo "Copying Fitz/MuPDF headers to native/include..."
cp -rf include/* "${INCLUDE_DIR}/"

echo "=== MuPDF v${VERSION} shared library built successfully ==="
ls -lh "${OUTPUT_DIR_X64}/libmupdf.so"
ls -lh "${OUTPUT_DIR_X86_64}/libmupdf.so"
