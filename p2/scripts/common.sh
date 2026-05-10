#!/usr/bin/env bash
set -euo pipefail

echo "[COMMON] Starting common setup..."

export DEBIAN_FRONTEND=noninteractive

apt-get update -y
apt-get upgrade -y

apt-get install -y \
  curl \
  ca-certificates \
  apt-transport-https \
  vim \
  git \
  gnupg \
  lsb-release \
  net-tools

# Disable swap (required for k8s)
swapoff -a || true
sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

# Kernel params
cat <<EOF >/etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

modprobe br_netfilter || true
sysctl --system

echo "[COMMON] Common setup finished."
