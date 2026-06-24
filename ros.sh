#!/bin/bash

# https://www.77bx.com/497.html
# by StarYu
# Version: 1.3

# 全局默认RouterOS版本号配置
DEFAULT_ROS_VERSION=$(wget -qO- https://upgrade.mikrotik.com/routeros/NEWESTa7.long-term | awk '{print $1}')

set -euo pipefail

# color
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_command() {
    command -v "$1" >/dev/null 2>&1 || {
        log_error "$1 is required but not installed. Aborting."
        exit 1
    }
}

# clean
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -f chr-*.*.*
    rm -f all_packages-*.*.*
    rm -f chr.*
    rm -f *.npk
    if [ "$1" = "INT" ]; then
        log_error "Operation was interrupted by the user (Ctrl C), script exiting!"
        exit 1  
    elif [ "$1" = "TERM" ]; then
        log_error "The script was forcibly terminated (TERM signal), script exited!"
        exit 1
    else
        log_info "Script exited normally, cleanup completed!"
        exit 0
    fi
}
trap 'cleanup INT' INT
trap 'cleanup TERM' TERM
trap 'cleanup EXIT' EXIT

# check  commands
required_commands=(wget gunzip fdisk lsblk)
for cmd in "${required_commands[@]}"; do
    check_command "$cmd"
done

# show welcome
clear
echo -e "${GREEN}=========================================${NC}"
echo -e "${GREEN}RouterOS CHR Installer 1.3${NC}"
echo -e "${GREEN}=========================================${NC}"
echo

# get version (使用全局默认值)
read -p "Please Input RouterOS Version (Default: ${DEFAULT_ROS_VERSION}): " ROS_VERSION
ROS_VERSION=${ROS_VERSION:-${DEFAULT_ROS_VERSION}}

# get admin password
get_admin_password() {
    read -sp "Enter RouterOS admin password: " admin_password
    echo
    while [ -z "$admin_password" ]; do
        read -sp "RouterOS Admin password cannot be blank. Please enter again: " admin_password
        echo
    done
}
get_admin_password

# bootmode
if [ -d "/sys/firmware/efi" ]; then
    log_info "Detected UEFI boot mode."
    BOOT_MODE="UEFI"
    CHR_NAME="chr-${ROS_VERSION}.img.zip"
else
    log_info "Detected BIOS legacy boot mode."
    BOOT_MODE="BIOS"
    CHR_NAME="chr-${ROS_VERSION}-legacy-bios.img.zip"
fi

# install software
if [ -f /etc/debian_version ]; then
    apt update && apt install -y unzip
elif [ -f /etc/redhat-release ]; then
    if command -v dnf >/dev/null; then
        dnf install -y unzip
    else
        yum install -y unzip
    fi
elif [ -f /etc/arch-release ]; then
    pacman -S --noconfirm unzip
else
    log_error "No "
    echo "Unsupported Linux distribution"
    exit 1
fi

# url
BASE_URL="https://github.com/elseif/MikroTikPatch/releases/download/${ROS_VERSION}"
CHR_URL="${BASE_URL}/${CHR_NAME}"
PACKAGES_URL="https://github.com/elseif/MikroTikPatch/releases/download/${ROS_VERSION}/all_packages-x86-${ROS_VERSION}.zip"

# download chr.img
log_info "Downloading RouterOS CHR ${ROS_VERSION} Image..."
wget -N  "$CHR_URL" 2>&1 || {
    log_error "Failed to download CHR Image"
    exit 1
}

# download Packages
log_info "Downloading RouterOS CHR ${ROS_VERSION} Packages..."
wget -N  "$PACKAGES_URL" 2>&1 || {
    log_warn "Failed to download container package"
    PACKAGES_DOWNLOAD_FAILED=true
}

# detect disk - FIXED: 直接使用 /dev/vda，排除光驱设备
DISK_DEVICE="/dev/vda"

# Operation continue
echo
echo -e "${RED}THIS WILL COMPLETELY DESTROY ALL DATA ON ($DISK_DEVICE)!!!${NC}"
read -p "Are you sure? Type 'Y' to continue: " confirmation
confirmation=$(echo "$confirmation" | tr '[:lower:]' '[:upper:]')
if [ "$confirmation" != "Y" ]; then
    log_info "Operation cancelled by user."
    exit 0
fi

# unzip img
log_info "Extracting RouterOS CHR Image..."
gunzip -c "${CHR_NAME}" > "chr.img" || {
    log_error "Failed to extract CHR Image"
    exit 1
}

# Mount image
log_info "Mounting image..."
umount /mnt 2>/dev/null || true
mkdir -p /mnt
LOOP_DEVICE=$(losetup -f --show chr.img)
mount -o loop,offset=33571840 $LOOP_DEVICE /mnt || {
    log_error "Failed to mount image"
    exit 1
}

# autorun
log_info "Writing autorun script..."
cat > /mnt/rw/autorun.scr <<EOF
/ip service set telnet disabled=yes
/ip service set ftp disabled=yes
/ip service set www disabled=yes
/ip service set ssh disabled=yes
/ip service set api disabled=yes
/ip service set api-ssl disabled=yes
/user set admin password=$admin_password
/system package enable container
EOF

# rosmode
log_info "Writing rosmode message..."
echo -e -n "\x4d\x32\x01\x00\x00\x29\x0b\x4d\x32\x1c\x00\x00\x01\x0a\x00\x00\x09\x00" > /mnt/rw/rosmode.msg

# install container
if [ "${PACKAGES_DOWNLOAD_FAILED:-false}" = false ]; then
    log_info "unzip packages..."
    unzip "all_packages-x86-${ROS_VERSION}.zip"
    log_info "Installing container package..."
    mkdir -p /mnt/var/pdb/container
    mv -f container-${ROS_VERSION}.npk /mnt/var/pdb/container/image
else
    log_warn "Skipping container package installation"
fi

# Unmount image
log_info "Unmounting image..."
umount /mnt

# write
log_info "Writing image to disk ($DISK_DEVICE). This may take several minutes..."
dd if=chr.img of=$DISK_DEVICE bs=4M oflag=sync status=progress || {
    log_error "Failed to write image to disk"
    exit 1
}

log_info "System will reboot in 5 seconds..."
echo "=================================================="
echo "RouterOS CHR ${ROS_VERSION} Installation completed successfully!"
echo "user: admin"
echo "password: (your set password)"
echo "=================================================="

sleep 1

echo 1 > /proc/sys/kernel/sysrq
echo b > /proc/sysrq-trigger
