#!/usr/bin/env bash
set -euo pipefail

echo "[K3S] Installing k3s server..."

VM_IP=$(hostname -I | awk '{print $1}')
echo "[K3S] Detected node IP: ${VM_IP}"

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 --node-ip ${VM_IP} --node-external-ip ${VM_IP}" \
  sh -

echo "[K3S] k3s server installed."

# Small wait for readiness
sleep 20

echo "[K3S] Current nodes:"
kubectl get nodes || sudo k3s kubectl get nodes || true

echo "[K3S] Done."
