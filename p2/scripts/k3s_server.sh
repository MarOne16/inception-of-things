#!/usr/bin/env bash
set -euo pipefail

echo "[K3S] Installing k3s server..."

# Use the private network IP, not the NAT interface
VM_IP=$(ip -4 addr show | grep -oP '(?<=inet\s)192\.168\.56\.\d+')
FLANNEL_IFACE=$(ip -4 addr | grep "192\.168\.56\." | awk '{print $NF}')
echo "[K3S] Detected IP: ${VM_IP} on interface: ${FLANNEL_IFACE}"

curl -sfL https://get.k3s.io | \
  INSTALL_K3S_EXEC="--write-kubeconfig-mode 644 \
    --node-ip ${VM_IP} \
    --node-external-ip ${VM_IP} \
    --flannel-iface ${FLANNEL_IFACE}" \
  sh -

echo "[K3S] k3s server installed. Waiting for node to be Ready..."
timeout 120 bash -c 'until kubectl get nodes 2>/dev/null | grep -q " Ready"; do sleep 5; done'

echo "[K3S] Node is Ready. Deploying applications..."
kubectl apply -f /tmp/k8s-configs/apps/app-configmaps.yaml
kubectl apply -f /tmp/k8s-configs/apps/app-deployments.yaml
kubectl apply -f /tmp/k8s-configs/ingress/apps-ingress.yaml

echo "[K3S] Current nodes:"
kubectl get nodes -o wide

echo "[K3S] All resources:"
kubectl get all
kubectl get ingress

echo "[K3S] Done."
