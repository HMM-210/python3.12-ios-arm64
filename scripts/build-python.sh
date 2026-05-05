#!/usr/bin/env bash
# ==============================================================================
# Script: build-python.sh — rootless palera1n edition
# ✅ التغيير الرئيسي: --prefix=/var/jb/usr/local بدلاً من /usr/local
# ==============================================================================

set -euxo pipefail

source "$(dirname "$0")/common-env.sh"

cd "$BUILD"

# ------------------------------------------------------------------------------
# Pre-flight Checks
# ------------------------------------------------------------------------------
if [ -z "${PYTHON_FOR_BUILD:-}" ]; then
    echo "Error: PYTHON_FOR_BUILD is not set." >&2
    exit 1
fi
if [ ! -x "$PYTHON_FOR_BUILD" ]; then
    echo "Error: PYTHON_FOR_BUILD='$PYTHON_FOR_BUILD' is not executable." >&2
    exit 1
fi

# ------------------------------------------------------------------------------
# Download CPython Source
# ------------------------------------------------------------------------------
for i in 1 2 3 4 5; do
  curl --fail --location --show-error -LO \
    "https://www.python.org/ftp/python/${PY_VER}/Python-${PY_VER}.tgz" && break || {
    echo "Error: Download failed (attempt $i). Retrying in 3s..." >&2
    sleep 3
  }
done

[ -f "Python-${PY_VER}.tgz" ] || { echo "Error: Python tarball missing." >&2; exit 1; }
tar xf "Python-${PY_VER}.tgz"
cd "Python-${PY_VER}"

# ------------------------------------------------------------------------------
# Patching
# ------------------------------------------------------------------------------
cat > Modules/Setup.local <<'EOF'
*disabled*
nis
EOF

REPO_ROOT="$(cd "$(dirname "$WORKDIR")" && pwd)"

# تطبيق الـ patch لتجاوز خطأ cross-compilation
PATCH_FILE="$REPO_ROOT/scripts/python-configure.patch"
gpatch -p0 < "$PATCH_FILE" || {
    echo "Warning: Patch failed. Falling back to sed..."
    cp configure configure.orig
    /usr/local/bin/gsed -ri \
      's/^[[:space:]]*as_fn_error[^\n]*cross build not supported[^\n]*$/  : # allow iOS cross build for $host/' \
      configure
}

# ------------------------------------------------------------------------------
# config.site — تجاوز اختبارات cross-compilation
# ------------------------------------------------------------------------------
cat > config.site <<'EOF'
ac_cv_file__dev_ptc=no
ac_cv_file__dev_ptmx=no
ac_cv_func_system=no
ac_cv_func_pipe2=no
ac_cv_func_forkpty=no
ac_cv_func_openpty=no
ac_cv_func_sendfile=no
ac_cv_func_preadv=no
ac_cv_func_pwritev=no
ac_cv_func_getentropy=no
ac_cv_func_utimensat=no
ac_cv_func_posix_fallocate=no
ac_cv_func_clock_settime=no
ac_cv_header_rpcsvc_yp_prot_h=no
ac_cv_header_rpcsvc_ypclnt_h=no
ac_cv_func_yp_get_default_domain=no
ac_cv_have_nis=no
ac_cv_func_getaddrinfo=yes
ac_cv_working_getaddrinfo=yes
ac_cv_buggy_getaddrinfo=no
ac_cv_func_getnameinfo=yes
EOF
export CONFIG_SITE="$PWD/config.site"

# ------------------------------------------------------------------------------
# Compiler Flags — إضافة مسارات الـ deps
# ------------------------------------------------------------------------------
export CPPFLAGS="-I$DEPS/openssl-ios/usr/local/include -I$DEPS/libffi-ios/usr/local/include"
export LDFLAGS="-L$DEPS/openssl-ios/usr/local/lib -L$DEPS/libffi-ios/usr/local/lib ${LDFLAGS}"
export LIBS="-lssl -lcrypto"
export PKG_CONFIG_PATH="$DEPS/libffi-ios/usr/local/lib/pkgconfig:$DEPS/openssl-ios/usr/local/lib/pkgconfig:${PKG_CONFIG_PATH:-}"
export LD="$CC"
export LDSHARED="$CC -bundle -undefined dynamic_lookup $LDFLAGS"
export LDCXXSHARED="$CXX -bundle -undefined dynamic_lookup $LDFLAGS"

# ------------------------------------------------------------------------------
# ✅ Configure — prefix هو /var/jb/usr/local (rootless)
# ------------------------------------------------------------------------------
./configure \
  --host="${HOST_TRIPLE}" \
  --build="$(uname -m)-apple-darwin" \
  --prefix="${INSTALL_PREFIX}" \
  --with-build-python="${PYTHON_FOR_BUILD}" \
  --with-openssl="$DEPS/openssl-ios/usr/local" \
  --with-ensurepip=install \
  --disable-test-modules

# تجاوز checksharedmods الذي يفشل في cross-compilation
awk 'BEGIN{skip=0}
  /^checksharedmods:/{print "checksharedmods:\n\t@true"; skip=1; next}
  skip && (/^\t/ || /^[[:space:]]*$/){next}
  skip {skip=0}
  {print}
' Makefile > Makefile.new && mv Makefile.new Makefile

# ------------------------------------------------------------------------------
# Build and Install
# ------------------------------------------------------------------------------
make -j"${JOBS}"
make install ENSUREPIP=no DESTDIR="$STAGE"

cd "$BUILD"
rm -f "Python-${PY_VER}.tgz"

# ------------------------------------------------------------------------------
# Post-Processing
# ------------------------------------------------------------------------------
# ✅ symlinks في المسار الصحيح rootless
PY_BINDIR="$STAGE${INSTALL_PREFIX}/bin"

ln -sf python3.12 "$PY_BINDIR/python3" || true

# Strip debug symbols
echo "Stripping binaries..."
find "$STAGE" -type f \( -name "*.dylib" -o -name "*.so" -o -path "$PY_BINDIR/*" \) | while read -r f; do
    if file -b "$f" | grep -q 'Mach-O'; then
        "$STRIP" -x "$f" || echo "Warning: strip failed on $f" >&2
    fi
done

# التوقيع بـ ldid
ENTITLEMENTS="$REPO_ROOT/scripts/entitlements.plist"
while IFS= read -r -d '' f; do
  if file -b "$f" | grep -q 'Mach-O'; then
    ldid -S"$ENTITLEMENTS" "$f" || echo "Warning: ldid failed on $f" >&2
  fi
done < <(find "$STAGE" -type f \( -name "*.dylib" -o -name "*.so" -o -path "$PY_BINDIR/*" \) -print0)

echo "✅ Python built and staged at: $STAGE${INSTALL_PREFIX}"
ls "$STAGE${INSTALL_PREFIX}/bin/" || true
