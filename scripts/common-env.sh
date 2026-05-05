#!/usr/bin/env bash
# ==============================================================================
# Script: common-env.sh — rootless palera1n edition
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Parallelization
# ------------------------------------------------------------------------------
JOBS="$(sysctl -n hw.ncpu)"

# Default iOS version target
MIN_IOS="${MIN_IOS:-15.0}"

# ------------------------------------------------------------------------------
# Directory Structure
# ------------------------------------------------------------------------------
WORKDIR="${WORKDIR:-$PWD/work}"
DEPS="$WORKDIR/deps"
BUILD="$WORKDIR/build"
STAGE="$WORKDIR/stage"

mkdir -p "$DEPS" "$BUILD" "$STAGE"

# ------------------------------------------------------------------------------
# ✅ rootless: prefix داخل /var/jb/
# ------------------------------------------------------------------------------
JBROOT="/var/jb"
INSTALL_PREFIX="$JBROOT/usr/local"

# ------------------------------------------------------------------------------
# iOS Toolchain
# ------------------------------------------------------------------------------
IOS_SDK="$(xcrun --sdk iphoneos --show-sdk-path)"
CC="$(xcrun --sdk iphoneos -f clang)"
CXX="$(xcrun --sdk iphoneos -f clang++)"
AR="$(xcrun --sdk iphoneos -f ar)"
RANLIB="$(xcrun --sdk iphoneos -f ranlib)"
STRIP="$(xcrun --sdk iphoneos -f strip)"
HOST_TRIPLE="aarch64-apple-darwin"

# ------------------------------------------------------------------------------
# Compiler Flags
# ------------------------------------------------------------------------------
export CFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${MIN_IOS} -fPIC"
export LDFLAGS="-arch arm64 -isysroot ${IOS_SDK} -miphoneos-version-min=${MIN_IOS}"

# ------------------------------------------------------------------------------
# Exports
# ------------------------------------------------------------------------------
export JOBS WORKDIR DEPS BUILD STAGE IOS_SDK HOST_TRIPLE
export JBROOT INSTALL_PREFIX
export CC CXX AR RANLIB STRIP
