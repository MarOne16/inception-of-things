#!/bin/bash
set -e

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ─── 1. Check Docker ──────────────────────────────────────────────────────────
echo "[+] Checking Docker..."
docker info &>/dev/null || { echo "[✗] Docker is not running. Start Docker Desktop first."; exit 1; }
echo "[✓] Docker is running"

# ─── 2. Install Helm ──────────────────────────────────────────────────────────
if ! command -v helm &>/dev/null; then
    echo "[+] Installing Helm..."
    if [ "$OS" = "Darwin" ]; then
        brew install helm
    else
        curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
    fi
else
    echo "[✓] Helm already installed: $(helm version --short)"
fi

# ─── 3. Install kubectl ───────────────────────────────────────────────────────
if ! command -v kubectl &>/dev/null; then
    echo "[+] Installing kubectl..."
    if [ "$OS" = "Darwin" ]; then
        brew install kubectl
    else
        curl -LO "https://dl.k8s.io/release/$(curl -Ls https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
        chmod +x kubectl && sudo mv kubectl /usr/local/bin/kubectl
    fi
else
    echo "[✓] kubectl already installed"
fi

# ─── 4. Install K3d ───────────────────────────────────────────────────────────
if ! command -v k3d &>/dev/null; then
    echo "[+] Installing K3d..."
    if [ "$OS" = "Darwin" ]; then
        brew install k3d
    else
        curl -s https://raw.githubusercontent.com/k3d-io/k3d/main/install.sh | bash
    fi
else
    echo "[✓] K3d already installed"
fi

# ─── 5. Create K3d cluster ────────────────────────────────────────────────────
if ! k3d cluster list 2>/dev/null | grep -q "mycluster"; then
    echo "[+] Creating K3d cluster..."
    k3d cluster create mycluster --port "8888:30080@loadbalancer" --port "8929:80@loadbalancer"
else
    echo "[✓] K3d cluster already exists"
fi

kubectl config use-context k3d-mycluster

# ─── 6. Create gitlab namespace ───────────────────────────────────────────────
echo "[+] Creating gitlab namespace..."
kubectl create namespace gitlab --dry-run=client -o yaml | kubectl apply -f -

# ─── 7. Add GitLab Helm repo ──────────────────────────────────────────────────
echo "[+] Adding GitLab Helm repo..."
helm repo add gitlab https://charts.gitlab.io/
helm repo update

# ─── 8. Install GitLab ────────────────────────────────────────────────────────
if ! helm list -n gitlab | grep -q "gitlab"; then
    echo "[+] Installing GitLab (this takes 5-10 minutes)..."
    helm install gitlab gitlab/gitlab \
        --namespace gitlab \
        --values "$SCRIPT_DIR/../confs/gitlab-values.yaml" \
        --timeout 15m \
        --wait
else
    echo "[✓] GitLab already installed"
fi

# ─── 9. Get root password ─────────────────────────────────────────────────────
echo ""
echo "[+] Waiting for GitLab secret to be ready..."
kubectl wait --for=condition=ready pod -l app=webservice -n gitlab --timeout=300s 2>/dev/null || true

PASS=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab \
    -o jsonpath="{.data.password}" 2>/dev/null | base64 --decode || echo "not ready yet - run: kubectl get secret gitlab-gitlab-initial-root-password -n gitlab -o jsonpath='{.data.password}' | base64 --decode")

echo ""
echo "========================================="
echo "  GitLab is ready!"
echo "  URL:      http://localhost:8929"
echo "  Login:    root"
echo "  Password: $PASS"
echo ""
echo "  If the page doesn't load yet, wait 2-3"
echo "  more minutes and refresh."
echo "========================================="
