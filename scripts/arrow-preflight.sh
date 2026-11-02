
#!/usr/bin/env bash

# ==========================================================
# ArrowOS 13 Beryllium - Build Automation Toolkit
# Preflight + Manifest + Sync + Signing Keys + Build
#
# Usage:
#   ./build.sh                 Audit only
#   ./build.sh --sync          Audit + sync source
#   ./build.sh --build         Audit + build
#   ./build.sh --sync --build  Full workflow
#
# Source changes are protected where possible.
# ==========================================================

set -Eeuo pipefail

ROOT="${ARROW_ROOT:-$HOME/arrow-13}"
KEY_DIR="$HOME/arrow-keys"
MANIFEST_DIR="$ROOT/.repo/local_manifests"
MANIFEST="$MANIFEST_DIR/beryllium.xml"

TARGET="${TARGET:-arrow_beryllium-user}"
JOBS="${JOBS:-4}"
CCACHE_SIZE="${CCACHE_SIZE:-100G}"

DO_SYNC=0
DO_BUILD=0

for arg in "$@"; do
    case "$arg" in
        --sync) DO_SYNC=1 ;;
        --build) DO_BUILD=1 ;;
        --help)
            echo "Usage: ./build.sh [--sync] [--build]"
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            exit 1
            ;;
    esac
done

LOG="$HOME/arrow-build-$(date +%Y%m%d-%H%M%S).log"

mkdir -p "$HOME"
exec > >(tee "$LOG") 2>&1

section() {
    echo
    echo "=================================================="
    echo "$1"
    echo "=================================================="
}

die() {
    echo "[ERROR] $*"
    exit 1
}

confirm() {
    read -r -p "$1 [y/N]: " answer
    [[ "$answer" == "y" || "$answer" == "Y" ]]
}

[[ -d "$ROOT" ]] || die "Source directory not found: $ROOT"
cd "$ROOT"

[[ -f .repo/repo/repo ]] || die "Repo client not found. Initialize source first."

# ----------------------------------------------------------
section "1. HOST ENVIRONMENT"

echo "Date: $(date)"
echo "Source: $ROOT"

uname -a
cat /etc/os-release | head -8

for cmd in git repo java python3 make gcc; do
    command -v "$cmd" || echo "[MISSING] $cmd"
done

df -h "$ROOT"
free -h || true

# ----------------------------------------------------------
section "2. SOURCE STRUCTURE"

for path in \
    build/make \
    build/soong \
    frameworks/base \
    packages/apps/Settings \
    system/core \
    bionic \
    device/xiaomi/beryllium \
    device/xiaomi/sdm845-common \
    kernel/xiaomi/sdm845 \
    vendor/xiaomi/beryllium \
    vendor/xiaomi/sdm845-common
do
    if [[ -d "$path" ]]; then
        echo "[OK] $path"
    else
        echo "[MISSING] $path"
    fi
done

# ----------------------------------------------------------
section "3. GIT STATUS AUDIT"

for path in \
    build/make \
    build/soong \
    frameworks/base \
    packages/apps/Settings \
    system/core \
    bionic \
    device/xiaomi/beryllium \
    device/xiaomi/sdm845-common \
    kernel/xiaomi/sdm845 \
    vendor/xiaomi/beryllium
do
    if git -C "$path" rev-parse --git-dir >/dev/null 2>&1; then
        echo
        echo "--- $path ---"
        git -C "$path" log -1 --format='%h %cs %s'
        git -C "$path" status --short
    else
        echo "[NOT GIT / MISSING] $path"
    fi
done

# ----------------------------------------------------------
section "4. DEVICE TREE AUDIT"

for file in \
    device/xiaomi/beryllium/BoardConfig.mk \
    device/xiaomi/beryllium/device.mk \
    device/xiaomi/beryllium/AndroidProducts.mk \
    device/xiaomi/sdm845-common/sdm845.mk
do
    [[ -f "$file" ]] && echo "[FOUND] $file" \
        || echo "[MISSING] $file"
done

grep -R -nE \
'PRODUCT_NAME|PRODUCT_DEVICE|PRODUCT_BRAND|TARGET_ARCH|TARGET_KERNEL|BOARD_BOOTIMAGE|BOARD_VENDORIMAGE|AB_OTA|PRODUCT_USE_DYNAMIC_PARTITIONS' \
device/xiaomi/beryllium \
device/xiaomi/sdm845-common \
--include='*.mk' 2>/dev/null | head -100 || true

# ----------------------------------------------------------
section "5. PARTITION AND FSTAB AUDIT"

find device/xiaomi/beryllium device/xiaomi/sdm845-common \
-type f -iname '*fstab*' -print 2>/dev/null || true

# ----------------------------------------------------------
section "6. KERNEL AUDIT"

KERNEL="kernel/xiaomi/sdm845"

if [[ -f "$KERNEL/Makefile" ]]; then
    grep -E '^(VERSION|PATCHLEVEL|SUBLEVEL|EXTRAVERSION) =' \
        "$KERNEL/Makefile" || true

    git -C "$KERNEL" log -8 \
        --format='%h %cs %s' 2>/dev/null || true

    git -C "$KERNEL" remote -v 2>/dev/null || true
fi

# ----------------------------------------------------------
section "7. VENDOR AUDIT"

for path in \
    vendor/xiaomi/beryllium \
    vendor/xiaomi/sdm845-common
do
    if [[ -d "$path" ]]; then
        find "$path" -maxdepth 2 -type f \
            \( -name '*.mk' -o -name '*.prop' -o -name '*.bp' \) \
            -print | head -50
    fi
done

# ----------------------------------------------------------
section "8. SECURITY PATCH AUDIT"

grep -nE \
'PLATFORM_SECURITY_PATCH|VENDOR_SECURITY_PATCH|BOOT_SECURITY_PATCH' \
build/make/core/version_defaults.mk \
device/xiaomi/beryllium/BoardConfig.mk \
device/xiaomi/sdm845-common/sdm845.mk \
2>/dev/null || true

# ----------------------------------------------------------
section "9. RESOURCE BACKUP CHECK"

find frameworks/base/core/res/res \
     packages/apps/Settings/res \
     -type f \( -name '*.bak' -o -name '*.orig' \) \
     -print 2>/dev/null || true

# ----------------------------------------------------------
section "10. MANIFEST SETUP"

mkdir -p "$MANIFEST_DIR"

if [[ -f "$MANIFEST" ]]; then
    echo "[INFO] Existing manifest found."

    if ! confirm "Backup and replace beryllium.xml?"; then
        die "Manifest setup cancelled."
    fi

    cp -p "$MANIFEST" \
       "$MANIFEST.backup.$(date +%Y%m%d-%H%M%S)"
fi

cat > "$MANIFEST" <<'XML'
<?xml version="1.0" encoding="UTF-8"?>
<manifest>
  <project path="device/xiaomi/beryllium"
    name="PewayOTR/android_device_xiaomi_beryllium"
    remote="github" revision="Arrow-13.1" />

  <project path="device/xiaomi/sdm845-common"
    name="PewayOTR/device_xiaomi_sdm845-common"
    remote="github" revision="thirteen" />

  <project path="vendor/xiaomi/beryllium"
    name="PewayOTR/proprietary_vendor_xiaomi-beryllium"
    remote="github" revision="13.0" />

  <project path="vendor/xiaomi/sdm845-common"
    name="PewayOTR/vendor_xiaomi_sdm845-common"
    remote="github" revision="thirteen" />

  <project path="kernel/xiaomi/sdm845"
    name="PewayOTR/android_kernel_xiaomi_sdm845"
    remote="github" revision="main" />

  <project path="hardware/xiaomi"
    name="PewayOTR/android_hardware_xiaomi"
    remote="github" revision="lineage-20" />

  <project path="vendor/xiaomi/miuicamera"
    name="PewayOTR/vendor_miuicamera"
    remote="github" revision="13" />
</manifest>
XML

echo "[OK] Local manifest written."

# ----------------------------------------------------------
section "11. SOURCE SYNC"

if [[ "$DO_SYNC" -eq 1 ]]; then
    echo "Sync jobs: $JOBS"

    if ! confirm "Run repo sync now?"; then
        die "Sync cancelled."
    fi

    repo sync -c -j"$JOBS" \
        --no-clone-bundle \
        --no-tags
else
    echo "[SKIP] Sync not requested."
fi

# ----------------------------------------------------------
section "12. SIGNING KEYS"

MAKE_KEY="$ROOT/development/tools/make_key"

[[ -x "$MAKE_KEY" ]] || die "make_key tool not found or not executable."

mkdir -p "$KEY_DIR"
chmod 700 "$KEY_DIR"

SUBJECT="/CN=ArrowOS/OU=PewayOTR/O=PewayOTR/L=Jakarta/ST=Jakarta/C=ID"

cd "$KEY_DIR"

for key in releasekey platform shared media networkstack sdk_sandbox; do
    if [[ -f "$key.pk8" && -f "$key.x509.pem" ]]; then
        echo "[EXISTS] $key"
        continue
    fi

    if [[ -e "$key.pk8" || -e "$key.x509.pem" ]]; then
        die "Incomplete key pair: $key. Check manually."
    fi

    echo "[GENERATE] $key"
    "$MAKE_KEY" "$key" "$SUBJECT"
done

chmod 600 ./*.pk8

cd "$ROOT"

# ----------------------------------------------------------
section "13. BUILD ENVIRONMENT"

source build/envsetup.sh

export USE_CCACHE=1

if command -v ccache >/dev/null 2>&1; then
    export CCACHE_EXEC="$(command -v ccache)"
    ccache -M "$CCACHE_SIZE"
    ccache -s
else
    echo "[WARNING] ccache not installed."
fi

export PRODUCT_DEFAULT_DEV_CERTIFICATE="$KEY_DIR/releasekey"

echo "Target: $TARGET"
echo "Signing certificate: $PRODUCT_DEFAULT_DEV_CERTIFICATE"

# ----------------------------------------------------------
section "14. BUILD"

if [[ "$DO_BUILD" -eq 1 ]]; then
    if ! confirm "Start build for $TARGET?"; then
        die "Build cancelled."
    fi

    lunch "$TARGET"

    mka bacon
else
    echo "[SKIP] Build not requested."
    echo "Run ./build.sh --build when ready."
fi

# ----------------------------------------------------------
section "15. COMPLETE"

echo "Log saved at:"
echo "$LOG"

echo "Source: $ROOT"
echo "Keys: $KEY_DIR"
echo "Manifest: $MANIFEST"

echo
echo "Automation completed."
