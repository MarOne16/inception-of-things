#!/usr/bin/env bash
set -euo pipefail

echo "[MASTER] Starting k3s server installation..."

# Detect this node's primary IP (the private network IP)
# Get the IP from the 192.168.56.0/24 subnet
MASTER_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.56\.\d+')
echo "[MASTER] Detected IP: ${MASTER_IP}"

# Install k3s server
# It will also install kubectl as /usr/local/bin/kubectl symlink
curl -sfL https://get.k3s.io | INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --node-ip ${MASTER_IP} --node-external-ip ${MASTER_IP}" sh -

echo "[MASTER] k3s server installed."

# Wait for k3s to fully start
echo "[MASTER] Waiting for k3s server to be ready..."
sleep 20

# -----------------------------
# Export token and IP for worker
# -----------------------------
TOKEN_FILE="/var/lib/rancher/k3s/server/node-token"
DEST_DIR="/tmp"
DEST_TOKEN="${DEST_DIR}/k3s_token"
DEST_IP="${DEST_DIR}/k3s_server_ip"

if [ -f "${TOKEN_FILE}" ]; then
  echo "[MASTER] Exporting join token to ${DEST_TOKEN}"
  mkdir -p "${DEST_DIR}"
  cp "${TOKEN_FILE}" "${DEST_TOKEN}"
  chmod 644 "${DEST_TOKEN}"

  echo "[MASTER] Saving server IP to ${DEST_IP}"
  echo "${MASTER_IP}" > "${DEST_IP}"
  chmod 644 "${DEST_IP}"
  
  # Start simple HTTP server to serve token files
  echo "[MASTER] Starting HTTP server on port 8000 to serve token..."
  cd /tmp
  nohup python3 -m http.server 8000 >/dev/null 2>&1 &
  sleep 2
else
  echo "[MASTER] ERROR: k3s token file not found at ${TOKEN_FILE}" >&2
  exit 1
fi

# -----------------------------
# Small check: list nodes (only master at this stage)
# -----------------------------
echo "[MASTER] Checking k3s nodes..."
kubectl get nodes || echo "[MASTER] kubectl not ready yet, this may still be fine."

echo "[MASTER] k3s server setup complete."
