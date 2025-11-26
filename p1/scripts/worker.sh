#!/usr/bin/env bash
set -euo pipefail

echo "[WORKER] Starting k3s agent installation..."

# Master server IP (from Vagrantfile)
K3S_SERVER_IP="192.168.56.110"

# Wait for token file to be available on master via HTTP
MAX_ATTEMPTS=30
SLEEP_SECONDS=5
ATTEMPT=1

echo "[WORKER] Waiting for token from master at ${K3S_SERVER_IP}..."

while [ "${ATTEMPT}" -le "${MAX_ATTEMPTS}" ]; do
  echo "[WORKER] Attempt ${ATTEMPT}/${MAX_ATTEMPTS}: downloading token from master..."
  
  # Try to download files from master via HTTP
  if curl -sf http://${K3S_SERVER_IP}:8000/k3s_token -o /tmp/k3s_token 2>/dev/null && \
     curl -sf http://${K3S_SERVER_IP}:8000/k3s_server_ip -o /tmp/k3s_server_ip 2>/dev/null; then
    echo "[WORKER] Successfully downloaded token from master"
    break
  fi
  
  sleep "${SLEEP_SECONDS}"
  ATTEMPT=$((ATTEMPT + 1))
done

if [ ! -f "/tmp/k3s_token" ] || [ ! -f "/tmp/k3s_server_ip" ]; then
  echo "[WORKER] ERROR: Could not download token from master after ${MAX_ATTEMPTS} attempts" >&2
  exit 1
fi

K3S_TOKEN=$(cat "/tmp/k3s_token")
K3S_SERVER_IP=$(cat "/tmp/k3s_server_ip")

echo "[WORKER] Got token and server IP: ${K3S_SERVER_IP}"

# Detect this node IP (private network IP)
# Get the IP from the 192.168.56.0/24 subnet
WORKER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.56\.\d+')
echo "[WORKER] Detected worker IP: ${WORKER_IP}"

# Install k3s agent and join cluster
curl -sfL https://get.k3s.io | \
  K3S_URL="https://${K3S_SERVER_IP}:6443" \
  K3S_TOKEN="${K3S_TOKEN}" \
  INSTALL_K3S_EXEC="--node-ip ${WORKER_IP} --node-external-ip ${WORKER_IP}" \
  sh -

echo "[WORKER] k3s agent installation complete."
