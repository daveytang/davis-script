#!/bin/bash

# 确保以 root 身份运行
if [ "$(id -u)" -ne 0 ]; then
   echo "请用 root 权限运行该脚本，例如：sudo bash install_panabit.sh"
   exit 1
fi

# 定义变量
INSTALL_DIR="/root/panabit"
TAR_URL="https://github.com/daveytang/davis-script/raw/refs/heads/main/PanabitFREE_TANGr7p5_20250901_Linux3.tar.gz"
TAR_FILE="${INSTALL_DIR}/PanabitFREE_TANGr7p5_20250901_Linux3.tar.gz"
EXTRACT_DIR="${INSTALL_DIR}/PanabitFREE_TANGr7p5_20250901_Linux3"

# 检查并安装依赖
check_and_install() {
    local pkg=$1
    if ! command -v "$pkg" >/dev/null 2>&1; then
        echo ">>> 未检测到 $pkg，正在安装..."
        apt-get update -y
        apt-get install -y "$pkg"
    else
        echo ">>> 已检测到 $pkg"
    fi
}

echo ">>> 检查依赖..."
check_and_install wget
check_and_install tar

# 创建 panabit 文件夹
echo ">>> 创建安装目录: ${INSTALL_DIR}"
mkdir -p "$INSTALL_DIR"

# 下载压缩包
echo ">>> 下载 Panabit 压缩包..."
wget -O "$TAR_FILE" "$TAR_URL"
if [ $? -ne 0 ]; then
   echo "下载失败，请检查网络或URL是否正确。"
   exit 1
fi

# 解压压缩包
echo ">>> 解压压缩包..."
tar -xzf "$TAR_FILE" -C "$INSTALL_DIR"

# 删除压缩包
echo ">>> 删除压缩包..."
rm -f "$TAR_FILE"

# 进入目录
cd "$EXTRACT_DIR" || { echo "解压目录不存在"; exit 1; }

# 执行 ipeinstall 脚本（保持交互和输出）
echo ">>> 开始执行 ipeinstall..."
exec bash ipeinstall
