#!/usr/bin/env bash
set -euo pipefail

if [ "$#" -lt 5 ]; then
  echo "用法: $0 <LOCAL_PUBLIC_IP> <REMOTE_PUBLIC_IP> <TUN_LOCAL_CIDR> <TUN_SUBNET> <WAN_IF> [GRE_NAME] [TTL]"
  echo "示例: $0 103.229.96.108 168.93.208.54 10.10.10.2/30 10.10.10.0/30 eth0 gre1 255"
  exit 1
fi

LOCAL_PUBLIC_IP="$1"
REMOTE_PUBLIC_IP="$2"
TUN_LOCAL_CIDR="$3"
TUN_SUBNET="$4"
WAN_IF="$5"
GRE_NAME="${6:-gre1}"
TTL="${7:-255}"

echo "[1/8] 加载 ip_gre 模块"
modprobe ip_gre

echo "[2/8] 删除旧 GRE 接口（如果存在）"
ip tunnel del "${GRE_NAME}" 2>/dev/null || true

echo "[3/8] 创建 GRE 隧道"
ip tunnel add "${GRE_NAME}" mode gre local "${LOCAL_PUBLIC_IP}" remote "${REMOTE_PUBLIC_IP}" ttl "${TTL}"

echo "[4/8] 配置 GRE 地址并启用接口"
ip addr flush dev "${GRE_NAME}" 2>/dev/null || true
ip addr add "${TUN_LOCAL_CIDR}" dev "${GRE_NAME}"
ip link set "${GRE_NAME}" up

echo "[5/8] 开启 IPv4 转发"
sysctl -w net.ipv4.ip_forward=1 >/dev/null
mkdir -p /etc/sysctl.d
cat > /etc/sysctl.d/99-gre-forward.conf <<'EOF'
net.ipv4.ip_forward=1
EOF
sysctl --system >/dev/null

echo "[6/8] 写入 iptables 规则（避免重复）"
iptables -C INPUT -p 47 -j ACCEPT 2>/dev/null || \
iptables -I INPUT 1 -p 47 -j ACCEPT

iptables -C FORWARD -i "${GRE_NAME}" -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -i "${GRE_NAME}" -j ACCEPT

iptables -C FORWARD -o "${GRE_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -o "${GRE_NAME}" -m state --state RELATED,ESTABLISHED -j ACCEPT

iptables -t nat -C POSTROUTING -s "${TUN_SUBNET}" -o "${WAN_IF}" -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING 1 -s "${TUN_SUBNET}" -o "${WAN_IF}" -j MASQUERADE

echo "[7/8] 显示当前状态"
echo "--- ip a show ${GRE_NAME} ---"
ip a show "${GRE_NAME}" || true
echo "--- ip tunnel show ---"
ip tunnel show || true
echo "--- default route ---"
ip route | grep default || true
echo "--- ip_forward ---"
sysctl net.ipv4.ip_forward || true
echo "--- iptables nat ---"
iptables -t nat -S | grep -E 'POSTROUTING|MASQUERADE' || true

echo "[8/8] 完成"
echo "GRE 已配置完成。"
