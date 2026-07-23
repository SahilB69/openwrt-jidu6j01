#!/bin/bash
set -euo pipefail

REPO_DIR=$(pwd)

sudo apt update
sudo apt install -y build-essential clang flex bison g++ gawk \
gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
python3-setuptools rsync swig unzip zlib1g-dev file wget ccache tree

git clone https://github.com/openwrt/openwrt.git
cd openwrt

git checkout v25.12.5

git config --global user.email "ci@build.local"
git config --global user.name "CI Builder"

# Fetch the PR
git fetch origin pull/23510/head:pr-23510 --force

# Cherry-pick commits
git log HEAD..pr-23510 \
    --reverse \
    --grep="jio\|jidu" \
    --regexp-ignore-case \
    --format="%H" |
xargs -r git cherry-pick -X theirs


echo "==> Adding initramfs-factory.ubi artifact"
# Add initramfs-factory.ubi artifact to JIDU6J01

FILOGIC_MK="target/linux/mediatek/image/filogic.mk"

for DEV in jiorouter_ax6000-jidu6j01; do
  # Skip if this device already has the artifact (idempotent)
  if awk "/^define Device\/${DEV}\$/,/^endef/" "$FILOGIC_MK" | grep -q "initramfs-factory.ubi"; then
    echo "[$DEV] initramfs-factory.ubi already present, skipping"
    continue
  fi

  echo "[$DEV] adding initramfs-factory.ubi artifact"

  # Insert the artifact block before the sysupgrade line, but ONLY inside this device's block
  awk -v dev="$DEV" '
    $0 == "define Device/" dev { indev=1 }
    indev && /^  IMAGE\/sysupgrade\.bin := sysupgrade-tar \| append-metadata$/ {
      print "ifeq ($(IB),)"
      print "ifneq ($(CONFIG_TARGET_ROOTFS_INITRAMFS),)"
      print "  ARTIFACTS := initramfs-factory.ubi"
      print "  ARTIFACT/initramfs-factory.ubi := append-image-stage initramfs-kernel.bin | ubinize-kernel"
      print "endif"
      print "endif"
      indev=0
    }
    { print }
  ' "$FILOGIC_MK" > "${FILOGIC_MK}.tmp" && mv "${FILOGIC_MK}.tmp" "$FILOGIC_MK"
done
echo "==> Done"

echo "==> Updating feeds"
./scripts/feeds update -a

echo "==> Installing feeds"
./scripts/feeds install -a

# Copy config dynamically
cp "$REPO_DIR/$DEVICE_CONFIG" .config

echo "==> Running make defconfig"
make defconfig

echo "==> Building OpenWrt"
make -j$(nproc)

echo "Build completed successfully! Artifacts are located in bin/targets/mediatek/filogic/"
