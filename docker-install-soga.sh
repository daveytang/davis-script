#!/bin/bash

# 创建目录
mkdir -p /root/trojan
mkdir -p /root/ss

# 更新 apt 包索引
apt update

# 安装 curl、sudo、wget
apt install -y curl sudo wget

# 安装 Docker
curl -fsSL https://get.docker.com | bash

# 启动并设置 Docker 开机自启
systemctl enable docker
systemctl start docker

# 安装完成提示
echo -e "\n✅ 安装完成！"
echo "已创建 /root/trojan 和 /root/ss"
echo "已安装 curl、sudo、wget 和 Docker"
echo -e "\n📌 本脚本由 dvs 提供，感谢使用！"
