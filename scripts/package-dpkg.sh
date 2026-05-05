#!/usr/bin/env bash
# ==============================================================================
# Script: package-dpkg.sh — rootless palera1n edition
# ✅ التغيير الرئيسي: الملفات تُنقل إلى var/jb/ بدلاً من usr/
# ==============================================================================

set -euxo pipefail

source "$(dirname "$0")/common-env.sh"

# ------------------------------------------------------------------------------
# Prepare Package Root
# ------------------------------------------------------------------------------
PKGROOT="$WORKDIR/pkgroot"
mkdir -p "$PKGROOT/DEBIAN"

# ✅ rootless: الملفات تذهب إلى var/jb/usr/ بدلاً من usr/
mkdir -p "$PKGROOT/var/jb"
mv "$STAGE/var/jb/usr" "$PKGROOT/var/jb/usr"

# ✅ symlink /var/jb/usr/bin/python3 → python3.12
mkdir -p "$PKGROOT/var/jb/usr/bin"
ln -sf "/var/jb/usr/local/bin/python3.12" "$PKGROOT/var/jb/usr/bin/python3"    || true
ln -sf "/var/jb/usr/local/bin/python3.12" "$PKGROOT/var/jb/usr/bin/python3.12" || true

# حجم الحزمة
INSTALLED_SIZE="$(du -sk "$PKGROOT/var/jb/usr" | awk '{print $1}')"

# ------------------------------------------------------------------------------
# Generate Control Files
# ------------------------------------------------------------------------------
CONTROL_TEMPLATE="$(dirname "$0")/../debian/control.in"
sed -e "s#\${PY_VER}#${PY_VER}#g" \
    -e "s#\${INSTALLED_SIZE}#${INSTALLED_SIZE}#g" \
    "$CONTROL_TEMPLATE" > "$PKGROOT/DEBIAN/control"

# changelog و copyright
CHANGELOG_FILE="$(dirname "$0")/../debian/changelog"
if [ -f "$CHANGELOG_FILE" ]; then
    mkdir -p "$PKGROOT/var/jb/usr/share/doc/com.k1tty-xz.python3"
    gzip -9 -n -c "$CHANGELOG_FILE" > \
      "$PKGROOT/var/jb/usr/share/doc/com.k1tty-xz.python3/changelog.gz"
fi

COPYRIGHT_FILE="$(dirname "$0")/../debian/copyright"
if [ -f "$COPYRIGHT_FILE" ]; then
    mkdir -p "$PKGROOT/var/jb/usr/share/doc/com.k1tty-xz.python3"
    cp "$COPYRIGHT_FILE" \
      "$PKGROOT/var/jb/usr/share/doc/com.k1tty-xz.python3/copyright"
fi

# ------------------------------------------------------------------------------
# ✅ PATH Configuration — rootless
# ------------------------------------------------------------------------------
mkdir -p "$PKGROOT/var/jb/etc/profile.d"
cat > "$PKGROOT/var/jb/etc/profile.d/python3.sh" <<'EOF'
export PATH="/var/jb/usr/local/bin:/var/jb/usr/bin:$PATH"
EOF
chmod 0644 "$PKGROOT/var/jb/etc/profile.d/python3.sh"

# ------------------------------------------------------------------------------
# ✅ postinst — يُشغَّل بعد التثبيت على الجهاز
# ------------------------------------------------------------------------------
cat > "$PKGROOT/DEBIAN/postinst" <<'EOF'
#!/bin/bash
PREFIX=/var/jb/usr/local

chmod +x "$PREFIX/bin/python3.12" 2>/dev/null || true
chmod +x "$PREFIX/bin/python3"    2>/dev/null || true

ln -sf "$PREFIX/bin/python3.12" /var/jb/usr/bin/python3    2>/dev/null || true
ln -sf "$PREFIX/bin/python3.12" /var/jb/usr/bin/python3.12 2>/dev/null || true

echo "✅ Python 3.12 installed at $PREFIX"
echo "   Run: python3.12 --version"
EOF
chmod 0755 "$PKGROOT/DEBIAN/postinst"

# ------------------------------------------------------------------------------
# ✅ prerm — يُشغَّل قبل الحذف
# ------------------------------------------------------------------------------
cat > "$PKGROOT/DEBIAN/prerm" <<'EOF'
#!/bin/bash
rm -f /var/jb/usr/bin/python3    2>/dev/null || true
rm -f /var/jb/usr/bin/python3.12 2>/dev/null || true
EOF
chmod 0755 "$PKGROOT/DEBIAN/prerm"

# ------------------------------------------------------------------------------
# Build .deb
# ------------------------------------------------------------------------------
OUTPUT="python3.12_${PY_VER}-1_iphoneos-arm.deb"
dpkg-deb --build --root-owner-group "$PKGROOT" "$WORKDIR/$OUTPUT"

echo "✅ Package built: $WORKDIR/$OUTPUT"
