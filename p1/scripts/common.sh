#!/usr/bin/env bash
set -euo pipefail

echo "[COMMON] Starting common setup..."

# -----------------------------
# Basic packages
# -----------------------------
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
  lsb-release

# -----------------------------
# Disable swap (required by k8s)
# -----------------------------
echo "[COMMON] Disabling swap..."
swapoff -a || true

# Comment out swap entries in /etc/fstab
sed -i.bak '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab || true

# -----------------------------
# Kernel params for k8s networking
# -----------------------------
echo "[COMMON] Setting sysctl values..."
cat <<EOF >/etc/sysctl.d/99-kubernetes-cri.conf
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF

modprobe br_netfilter || true
sysctl --system

# -----------------------------
# Setup SSH for inter-VM communication
# -----------------------------
echo "[COMMON] Setting up SSH for inter-VM communication..."

# Configure SSH client to disable strict host key checking for private network
sudo -u vagrant bash -c 'cat > /home/vagrant/.ssh/config << EOF
Host 192.168.56.*
    StrictHostKeyChecking no
    UserKnownHostsFile=/dev/null
    IdentityFile ~/.ssh/insecure_private_key
EOF'
sudo -u vagrant chmod 600 /home/vagrant/.ssh/config

echo "[COMMON] Common setup finished."
