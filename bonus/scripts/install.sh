#!/bin/bash
# Bonus: K3d + GitLab + ArgoCD watching local GitLab repo (fully automated)
set -e

OS="$(uname -s)"
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# ── Check Docker ──────────────────────────────────────────────────────────────
docker info &>/dev/null || { echo "[✗] Docker not running."; exit 1; }
echo "[✓] Docker"

# ── Install Helm (package manager — used to install GitLab) ──────────────────
if ! command -v helm &>/dev/null; then
    [ "$OS" = "Darwin" ] && brew install helm || curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
fi
echo "[✓] Helm"

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

# ── Create cluster (8888:30080 → app NodePort) ────────────────────────────────
k3d cluster list 2>/dev/null | grep -q "mycluster" \
    || k3d cluster create mycluster --port "8888:30080@loadbalancer"
kubectl config use-context k3d-mycluster
echo "[✓] Cluster"

# ── Create namespaces ─────────────────────────────────────────────────────────
for ns in argocd dev gitlab; do
    kubectl create namespace $ns --dry-run=client -o yaml | kubectl apply -f -
done
echo "[✓] Namespaces"

# ── Install GitLab with Helm ──────────────────────────────────────────────────
helm repo add gitlab https://charts.gitlab.io/ &>/dev/null && helm repo update &>/dev/null
if ! helm list -n gitlab 2>/dev/null | grep -q "gitlab"; then
    echo "[+] Installing GitLab (5-10 min)..."
    helm install gitlab gitlab/gitlab \
        --namespace gitlab \
        --values "$SCRIPT_DIR/../confs/gitlab-values.yaml" \
        --timeout 15m || true
fi
echo "[+] Waiting for GitLab..."
kubectl wait --for=condition=available --timeout=600s deployment/gitlab-webservice-default -n gitlab
echo "[✓] GitLab"

# ── Temporary port-forward to access GitLab API during setup ─────────────────
kubectl port-forward svc/gitlab-webservice-default -n gitlab 8929:8181 &>/dev/null &
trap "kill $! 2>/dev/null || true" EXIT
sleep 5

# ── Get GitLab root password from Kubernetes secret ───────────────────────────
GITLAB_PASS=$(kubectl get secret gitlab-gitlab-initial-root-password -n gitlab \
    -o jsonpath="{.data.password}" | base64 --decode)

# ── Create GitLab token via Rails runner (no UI needed) ──────────────────────
echo "[+] Creating GitLab token..."
TOOLBOX=$(kubectl get pod -n gitlab -l app=toolbox -o jsonpath='{.items[0].metadata.name}')
GITLAB_TOKEN=$(kubectl exec -n gitlab $TOOLBOX -- gitlab-rails runner \
    "t = User.find_by_username('root').personal_access_tokens.create(name: 'argocd', scopes: [:api, :read_repository, :write_repository], expires_at: 365.days.from_now); t.save!; puts t.token" \
    2>/dev/null)
echo "[✓] Token created"

# ── Create repo in local GitLab via API ───────────────────────────────────────
curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "Content-Type: application/json" \
    http://localhost:8929/api/v4/projects \
    -d '{"name":"argocd-app","visibility":"public"}' &>/dev/null
echo "[✓] Repo created"

# ── Push app manifests to GitLab via API (base64 encoded) ─────────────────────
echo "[+] Pushing manifests..."

DEPLOYMENT=$(base64 <<'EOF'
apiVersion: apps/v1
kind: Deployment
metadata:
  name: wil-playground
  namespace: dev
  labels:
    app: wil-playground
spec:
  replicas: 1
  selector:
    matchLabels:
      app: wil-playground
  template:
    metadata:
      labels:
        app: wil-playground
    spec:
      containers:
        - name: wil-playground
          image: wil42/playground:v1
          ports:
            - containerPort: 8888
EOF
)

SERVICE=$(base64 <<'EOF'
apiVersion: v1
kind: Service
metadata:
  name: wil-playground
  namespace: dev
spec:
  selector:
    app: wil-playground
  ports:
    - protocol: TCP
      port: 8888
      targetPort: 8888
      nodePort: 30080
  type: NodePort
EOF
)

curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "Content-Type: application/json" \
    "http://localhost:8929/api/v4/projects/root%2Fargocd-app/repository/files/deployment.yaml" \
    -d "{\"branch\":\"main\",\"content\":\"$DEPLOYMENT\",\"encoding\":\"base64\",\"commit_message\":\"add deployment\"}" &>/dev/null

curl -s -X POST -H "PRIVATE-TOKEN: $GITLAB_TOKEN" -H "Content-Type: application/json" \
    "http://localhost:8929/api/v4/projects/root%2Fargocd-app/repository/files/service.yaml" \
    -d "{\"branch\":\"main\",\"content\":\"$SERVICE\",\"encoding\":\"base64\",\"commit_message\":\"add service\"}" &>/dev/null
echo "[✓] Manifests pushed"

# ── Install ArgoCD ────────────────────────────────────────────────────────────
if ! kubectl get deployment argocd-server -n argocd &>/dev/null; then
    echo "[+] Installing ArgoCD..."
    kubectl apply --server-side --force-conflicts -n argocd \
        -f https://raw.githubusercontent.com/argoproj/argo-cd/stable/manifests/install.yaml
    kubectl wait --for=condition=available --timeout=300s deployment/argocd-server -n argocd
fi
echo "[✓] ArgoCD"

# ── Connect ArgoCD to local GitLab (internal DNS — no port-forward needed) ────
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: wil-playground
  namespace: argocd
spec:
  project: default
  source:
    repoURL: http://gitlab-webservice-default.gitlab:8181/root/argocd-app.git
    targetRevision: HEAD
    path: .
  destination:
    server: https://kubernetes.default.svc
    namespace: dev
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF
echo "[✓] ArgoCD connected to local GitLab"

# ── Done ──────────────────────────────────────────────────────────────────────
ARGOCD_PASS=$(kubectl get secret argocd-initial-admin-secret -n argocd \
    -o jsonpath="{.data.password}" | base64 --decode)
echo ""
echo "================================="
echo "  GitLab:"
echo "    1. echo '127.0.0.1 gitlab.localhost' | sudo tee -a /etc/hosts"
echo "    2. sudo kubectl port-forward svc/gitlab-webservice-default -n gitlab 80:8181"
echo "    3. http://gitlab.localhost  (root / $GITLAB_PASS)"
echo ""
echo "  ArgoCD: kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo "  UI: https://localhost:8080  (admin / $ARGOCD_PASS)"
echo ""
echo "  App: curl http://localhost:8888/"
echo "================================="
