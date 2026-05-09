#!/bin/bash
# Part 3: K3d + ArgoCD + wil42/playground deployed from GitHub
set -e

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Install Docker ────────────────────────────────────────────────────────────
if ! command -v docker &>/dev/null; then
    [ "$OS" = "Darwin" ] && { brew install --cask docker; open -a Docker; echo "[!] Open Docker Desktop and re-run."; exit 0; }
    curl -fsSL https://get.docker.com | sh && sudo usermod -aG docker "$USER" && sudo systemctl enable --now docker
fi
docker info &>/dev/null || { echo "[✗] Docker not running."; exit 1; }
echo "[✓] Docker"

# ── Install kubectl ───────────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
    [ "$OS" = "Darwin" ] && brew install kubectl || {
        curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
    }
fi
echo "[✓] kubectl"

# ── Install K3d ───────────────────────────────────────────────────────────────
if ! command -v k3d &>/dev/null; then
    [ "$OS" = "Darwin" ] && brew install k3d || curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
fi
echo "[✓] K3d"

# ── Create cluster (localhost:8888 → NodePort 30080 → app pod) ───────────────
k3d cluster list 2>/dev/null | grep -q "mycluster" \
    || k3d cluster create mycluster --port "8888:30080@loadbalancer"
kubectl config use-context k3d-mycluster
echo "[✓] Cluster"

# ── Create namespaces ─────────────────────────────────────────────────────────
for ns in argocd dev; do
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done
echo "[✓] Namespaces"

# ── Install ArgoCD ────────────────────────────────────────────────────────────
echo "[+] Installing ArgoCD (~2 min)..."
kubectl apply --server-side --force-conflicts -n argocd \
    -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
echo "[✓] ArgoCD"

# ── Apply ArgoCD Application (watches GitHub repo, deploys to dev) ────────────
kubectl apply --server-side --force-conflicts -f "$SCRIPT_DIR/../confs/argocd-app.yaml"
echo "[✓] ArgoCD Application applied"

# ── Done ─────────────────────────────────────────────────────────────────────
PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath="{.data.password}" | base64 --decode)
echo ""
echo "================================="
echo "  App:  curl http://localhost:8888/"
echo "  ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  UI: https://localhost:8080  (admin / $PASS)"
echo "================================="
