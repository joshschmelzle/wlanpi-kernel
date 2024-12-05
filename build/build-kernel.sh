#!/bin/bash

# Build script for cross-compiling the Linux kernel for Raspberry Pi CM4/RPI4
# and packaging it into a Debian package
# Target: ARM64, Distribution: Debian Bookworm
# Author: Jerry Olla <jerryolla@gmail.com>

set -e  # Exit immediately if a command exits with a non-zero status

# Enable detailed logging
LOG_FILE="build_kernel.log"
exec > >(tee -i "$LOG_FILE")
exec 2>&1

# Variables
KERNEL_REPO="https://github.com/raspberrypi/linux.git"
KERNEL_BRANCH="rpi-6.12.y"
KERNEL_SRC_DIR="linux"
OUTPUT_PATH="$(pwd)/output"  # Output directory
CROSS_COMPILE="aarch64-linux-gnu-"
ARCH="arm64"
BASE_CONFIG="bcm2711_defconfig"
CUSTOM_CONFIG="wlanpi_v8_defconfig"  # Updated configuration filename
NUM_CORES=$(nproc)

# Define the new kernel image name here
KERNEL_IMAGE_NAME="wlanpi-kernel8.img"

IMAGE_OUTPUT="${OUTPUT_PATH}/boot/firmware/${KERNEL_IMAGE_NAME}"
DTB_OUTPUT_DIR="${OUTPUT_PATH}/boot/firmware/"
DTBO_OUTPUT_DIR="${OUTPUT_PATH}/boot/firmware/overlays/"
MODULES_OUTPUT_DIR="${OUTPUT_PATH}/lib/modules"
PACKAGE_DIR="$(pwd)/wlanpi-kernel-package"
PACKAGE_NAME="wlanpi-kernel"

# Save the main build directory before changing directories
BUILD_DIR="$(pwd)"

# Functions
error_exit() {
    echo "Error on line $1"
    exit 1
}
trap 'error_exit $LINENO' ERR

# Verify that OUTPUT_PATH is set
if [ -z "$OUTPUT_PATH" ]; then
    echo "ERROR: OUTPUT_PATH is not set."
    exit 1
fi

# Create output directories if they don't exist
echo "Creating output directories..."
mkdir -p "$(dirname "$IMAGE_OUTPUT")"
mkdir -p "$DTB_OUTPUT_DIR"
mkdir -p "$DTBO_OUTPUT_DIR"
mkdir -p "$MODULES_OUTPUT_DIR"

# Clone the kernel source
if [ ! -d "$KERNEL_SRC_DIR" ]; then
    echo "Cloning kernel source from $KERNEL_REPO..."
    git clone --depth=1 -b "$KERNEL_BRANCH" "$KERNEL_REPO" "$KERNEL_SRC_DIR"
else
    echo "Kernel source directory already exists. Updating..."
    cd "$KERNEL_SRC_DIR"
    git fetch origin "$KERNEL_BRANCH"
    git checkout "$KERNEL_BRANCH"
    git reset --hard "origin/$KERNEL_BRANCH"
    cd "$BUILD_DIR"  # Return to main build directory
fi

# Change to kernel source directory
cd "$KERNEL_SRC_DIR"

# Set up cross-compilation environment
export ARCH="$ARCH"
export CROSS_COMPILE="$CROSS_COMPILE"

# Clean previous builds
echo "Cleaning previous builds..."
make mrproper

# Load base config
echo "Loading base config: $BASE_CONFIG..."
make "$BASE_CONFIG"

# Merge custom config
echo "Merging custom config: $CUSTOM_CONFIG..."
if [ -f "$BUILD_DIR/$CUSTOM_CONFIG" ]; then
    # Use merge_config.sh to merge the custom config fragment with the base config
    ./scripts/kconfig/merge_config.sh -m .config "$BUILD_DIR/$CUSTOM_CONFIG" .config
    # Apply the merged configuration
    make olddefconfig
else
    echo "ERROR: Custom config file $CUSTOM_CONFIG not found in $BUILD_DIR."
    exit 1
fi

# Start the build
echo "Starting kernel build..."

echo "Building Image..."
make -j"$NUM_CORES" Image

echo "Building modules..."
make -j"$NUM_CORES" modules

echo "Installing modules to $MODULES_OUTPUT_DIR..."
# Install modules to the specified output directory
make INSTALL_MOD_PATH="$OUTPUT_PATH" modules_install

echo "Building Device Tree Blobs (DTBs)..."
make -j"$NUM_CORES" dtbs

# Retrieve the kernel version
KERNEL_VERSION=$(make kernelrelease)
echo "Kernel version: $KERNEL_VERSION"

# Set PACKAGE_VERSION dynamically based on KERNEL_VERSION and current date/time
# Example: 6.12.1-20231004.150000 (YYYYMMDD.HHMMSS)
TIMESTAMP=$(date +%Y%m%d.%H%M%S)
PACKAGE_VERSION="${KERNEL_VERSION}-${TIMESTAMP}"
echo "Package version set to: $PACKAGE_VERSION"

# Verify build outputs
if [ ! -f "arch/arm64/boot/Image" ]; then
    echo "ERROR: Kernel image not found!"
    exit 1
fi

# Copy kernel image with the new name
echo "Copying kernel image to $IMAGE_OUTPUT..."
cp arch/arm64/boot/Image "$IMAGE_OUTPUT"

# Copy DTBs
echo "Copying DTBs to $DTB_OUTPUT_DIR..."
find arch/arm64/boot/dts/ -name '*.dtb' -exec cp {} "$DTB_OUTPUT_DIR" \;

# Copy DTBOs
echo "Copying DTBOs to $DTBO_OUTPUT_DIR..."
find arch/arm64/boot/dts/overlays/ -name '*.dtbo' -exec cp {} "$DTBO_OUTPUT_DIR" \;

# Verify modules installation
if [ -d "${MODULES_OUTPUT_DIR}/${KERNEL_VERSION}" ]; then
    echo "Modules successfully installed to ${MODULES_OUTPUT_DIR}/${KERNEL_VERSION}"
else
    echo "ERROR: Modules were not installed correctly."
    exit 1
fi

# Prepare Debian package
echo "Preparing Debian package..."

# Clean previous package directory if exists
if [ -d "$PACKAGE_DIR" ]; then
    rm -rf "$PACKAGE_DIR"
fi

mkdir -p "$PACKAGE_DIR/DEBIAN"
mkdir -p "$PACKAGE_DIR/usr/local/lib/wlanpi-kernel/boot/firmware/overlays"
mkdir -p "$PACKAGE_DIR/usr/local/lib/wlanpi-kernel/lib/modules/"
mkdir -p "$PACKAGE_DIR/lib/modules/"

# Copy kernel image and DTBs to package directory
cp "$IMAGE_OUTPUT" "$PACKAGE_DIR/usr/local/lib/wlanpi-kernel/boot/firmware/"
cp "$DTB_OUTPUT_DIR"*.dtb "$PACKAGE_DIR/usr/local/lib/wlanpi-kernel/boot/firmware/"
cp "$DTBO_OUTPUT_DIR"*.dtbo "$PACKAGE_DIR/usr/local/lib/wlanpi-kernel/boot/firmware/overlays/"

# Copy modules to package directory
cp -r "$MODULES_OUTPUT_DIR/$KERNEL_VERSION" "$PACKAGE_DIR/usr/local/lib/wlanpi-kernel/lib/modules/"

# Create DEBIAN/control file with updated Maintainer Information and without firmware-linux dependency
cat <<EOF > "$PACKAGE_DIR/DEBIAN/control"
Package: $PACKAGE_NAME
Version: $PACKAGE_VERSION
Section: kernel
Priority: optional
Architecture: arm64
Maintainer: Jerry Olla <jerryolla@gmail.com>
Depends: libc6 (>= 2.29)
Description: Custom Linux kernel for Raspberry Pi CM4/RPI4 with WLAN Pi v8 configuration for Debian Bookworm
 This package contains a custom-built Linux kernel image, Device Tree Blobs (DTBs),
 and kernel modules tailored for the WLAN Pi v8 configuration on Raspberry Pi CM4/RPI4 running Debian Bookworm.
EOF

# Create DEBIAN/postinst script
cat <<'EOF' > "$PACKAGE_DIR/DEBIAN/postinst"
#!/bin/bash
set -e

# Variables
FIRMWARE_DIR="/boot/firmware"
PACKAGE_KERNEL_DIR="/usr/local/lib/wlanpi-kernel/boot/firmware"
CONFIG_TXT="$FIRMWARE_DIR/config.txt"
KERNEL_IMAGE="wlanpi-kernel8.img"  # Updated kernel image name

echo "Post-installation: Installing kernel image and DTBs to $FIRMWARE_DIR..."

# Ensure the firmware directory exists
if [ ! -d "$FIRMWARE_DIR" ]; then
    echo "ERROR: Firmware directory $FIRMWARE_DIR does not exist."
    exit 1
fi

# Overwrite existing kernel image without backup
echo "Copying kernel image..."
cp -f "$PACKAGE_KERNEL_DIR/$KERNEL_IMAGE" "$FIRMWARE_DIR/"

# Copy DTBs
echo "Copying DTBs..."
cp -f "$PACKAGE_KERNEL_DIR/"*.dtb "$FIRMWARE_DIR/"
cp -f "$PACKAGE_KERNEL_DIR/overlays/"*.dtbo "$FIRMWARE_DIR/overlays/"

# Ensure config.txt contains the kernel parameter
echo "Verifying $CONFIG_TXT for kernel parameter..."
if grep -q "^kernel=" "$CONFIG_TXT"; then
    echo "kernel parameter already set in $CONFIG_TXT. Updating to $KERNEL_IMAGE..."
    sed -i "s|^kernel=.*|kernel=$KERNEL_IMAGE|" "$CONFIG_TXT"
else
    echo "kernel parameter not found in $CONFIG_TXT. Adding it..."
    echo "kernel=$KERNEL_IMAGE" >> "$CONFIG_TXT"
fi

echo "Kernel image and DTBs installed successfully."

# Optionally, you can add commands here to update the bootloader or reboot the system
# For example:
# sudo rpi-eeprom-update -d -a

# Optionally, prompt for a reboot
# read -p "Reboot now to apply the new kernel? [y/N] " confirm && [[ $confirm == [yY] ]] && reboot

exit 0
EOF

# Make postinst script executable
chmod 755 "$PACKAGE_DIR/DEBIAN/postinst"

# Create the Debian package inside the output directory with the kernel version and revision
echo "Building Debian package..."
dpkg-deb --build "$PACKAGE_DIR" "$OUTPUT_PATH/$PACKAGE_NAME"_"$PACKAGE_VERSION"_arm64.deb

echo "Debian package $PACKAGE_NAME_$PACKAGE_VERSION_arm64.deb created successfully in $OUTPUT_PATH."

# Clean up temporary package directory
echo "Cleaning up temporary package directory..."
rm -rf "$PACKAGE_DIR"

echo "Kernel build, module installation, and package creation completed successfully."

