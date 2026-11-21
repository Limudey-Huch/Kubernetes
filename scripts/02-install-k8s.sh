#!/usr/bin/env bash
# =============================================================================
# 02-install-k8s.sh — Install a single-node Kubernetes cluster with kubeadm
#
# Follows chapter 01 (01-platform-architecture.md) step by step:
#   1. Prepare Ubuntu        (swap off, kernel modules, sysctl)
#   2. Container runtime     (containerd, systemd cgroup driver)
#   3. Kubernetes packages   (kubeadm, kubelet, kubectl + crictl config)
#   4. Create the cluster    (kubeadm init)
#   5. Pod network           (Flannel CNI)
#   6. Allow workloads       (remove control-plane taint — single node)
#   7. Smoke test            (nginx Deployment, then removed)
#
# Run order: 01-reset-vm.sh -> 03-static-ip.sh -> 02-install-k8s.sh
#
# Usage:
#   ./02-install-k8s.sh                  # dry run: checks + plan, no changes
#   ./02-install-k8s.sh --yes            # install
#
# Options:
#   --k8s-version 1.36     Kubernetes minor version (default 1.36)
#   --ip ADDR              Node / API server IP (default: IP of the default-route interface)
#   --pod-cidr CIDR        Pod network (default 10.244.0.0/16 — what Flannel expects)
#   --yes                  Apply
# =============================================================================
set -euo pipefail

K8S_VERSION="1.36"
NODE_IP=""
POD_CIDR="10.244.0.0/16"
FLANNEL_URL="https://github.com/flannel-io/flannel/releases/latest/download/kube-flannel.yml"
APPLY=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --k8s-version) K8S_VERSION="$2"; shift 2 ;;
    --ip)          NODE_IP="$2"; shift 2 ;;
    --pod-cidr)    POD_CIDR="$2"; shift 2 ;;
    --yes)         APPLY=true; shift ;;
    -h|--help)     sed -n '2,26p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

c_blue='\033[1;34m'; c_yel='\033[1;33m'; c_grn='\033[1;32m'; c_red='\033[1;31m'; c_off='\033[0m'
step() { echo -e "\n${c_blue}==> $*${c_off}"; }
ok()   { echo -e "   ${c_grn}OK${c_off}    $*"; }
warn() { echo -e "   ${c_yel}WARN${c_off}  $*"; WARNINGS=$((WARNINGS+1)); }
fail() { echo -e "   ${c_red}FAIL${c_off}  $*"; ERRORS=$((ERRORS+1)); }
plan() { echo -e "   ${c_yel}[would]${c_off} $*"; }
die()  { echo -e "\n${c_red}ERROR:${c_off} $*"; exit 1; }
WARNINGS=0; ERRORS=0

[[ $EUID -eq 0 ]] && die "Run as your regular user (it uses sudo), not as root."
sudo true || die "This script needs sudo."

# =============================================================================
# Preflight checks (always run)
# =============================================================================
step "Preflight checks"

. /etc/os-release
[[ "$ID" == "ubuntu" ]] && ok "OS: $PRETTY_NAME ($(dpkg --print-architecture))" || fail "Not Ubuntu: $PRETTY_NAME"

CPUS=$(nproc); MEM_GB=$(awk '/MemTotal/{printf "%.1f", $2/1048576}' /proc/meminfo)
DISK_FREE_GB=$(df -BG --output=avail / | tail -1 | tr -dc 0-9)
(( CPUS >= 2 )) || fail "CPU: $CPUS (kubeadm needs at least 2)"
(( CPUS >= 4 )) && ok "CPU: $CPUS" || { (( CPUS >= 2 )) && warn "CPU: $CPUS (4+ recommended for the full course)"; }
awk "BEGIN{exit !($MEM_GB >= 7)}" && ok "RAM: ${MEM_GB} GB" || warn "RAM: ${MEM_GB} GB (8 GB+ recommended)"
(( DISK_FREE_GB >= 20 )) && ok "Free disk: ${DISK_FREE_GB} GB" || warn "Free disk: ${DISK_FREE_GB} GB (20 GB+ recommended)"

IFACE=$(ip -4 route show default | awk '{print $5; exit}')
[[ -n "$NODE_IP" ]] || NODE_IP=$(ip -4 -o addr show "$IFACE" | awk '{print $4; exit}' | cut -d/ -f1)
[[ -n "$NODE_IP" ]] || die "Could not detect node IP. Use --ip."
if ip -4 addr show "$IFACE" | grep -q ' dynamic '; then
  warn "Node IP $NODE_IP on $IFACE is DHCP — run 03-static-ip.sh first"
else
  ok "Node IP: $NODE_IP on $IFACE (static)"
fi
ok "Hostname: $(hostname)"

swapon --show | grep -q . && warn "Swap is on (will be turned off)" || ok "Swap is off"

if command -v docker >/dev/null || dpkg -s containerd.io >/dev/null 2>&1; then
  fail "Docker / containerd.io found — run 01-reset-vm.sh first"
else
  ok "No Docker / containerd.io"
fi

for p in 6443 2379 2380 10250 10257 10259; do
  if sudo ss -ltn "sport = :$p" | grep -q LISTEN; then
    [[ -f /etc/kubernetes/admin.conf ]] || fail "Port $p already in use"
  fi
done
ok "Kubernetes ports checked"

if curl -fsSL -o /dev/null "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key"; then
  ok "Kubernetes v${K8S_VERSION} repo reachable"
else
  fail "Cannot reach Kubernetes v${K8S_VERSION} repo (bad version or no internet)"
fi

[[ -f /etc/kubernetes/admin.conf ]] && warn "Cluster already initialized — kubeadm init will be skipped"

(( ERRORS == 0 )) || die "$ERRORS preflight check(s) failed. Fix them and run again."

# =============================================================================
# Plan (dry run)
# =============================================================================
if ! $APPLY; then
  step "Plan"
  plan "1. swapoff, load overlay + br_netfilter, set sysctl (ip_forward, bridge-nf-call)"
  plan "2. apt install containerd ($(apt-cache policy containerd | awk '/Candidate/{print $2}')), set SystemdCgroup = true"
  plan "3. add pkgs.k8s.io v${K8S_VERSION} repo, install kubelet kubeadm kubectl (held) + cri-tools, configure crictl"
  plan "4. kubeadm init --apiserver-advertise-address=${NODE_IP} --pod-network-cidr=${POD_CIDR}"
  plan "   copy admin.conf to ~/.kube/config"
  plan "5. kubectl apply Flannel (${FLANNEL_URL})"
  plan "6. remove taint node-role.kubernetes.io/control-plane"
  plan "7. smoke test: nginx Deployment -> Running -> deleted"
  echo -e "\n${c_yel}DRY RUN — nothing changed. Re-run with --yes to install.${c_off}"
  exit 0
fi

LOG=/tmp/k8s-install-$(date +%Y%m%d-%H%M%S).log
echo -e "\nInstalling. Full log: $LOG"
quiet() { "$@" >>"$LOG" 2>&1; }

# =============================================================================
# 1. Prepare Ubuntu
# =============================================================================
step "1. Prepare Ubuntu"
sudo swapoff -a
sudo sed -i -E '/^[^#].*\sswap\s/ s/^/#/' /etc/fstab
ok "Swap off (now and after reboot)"

cat <<EOF | sudo tee /etc/modules-load.d/k8s.conf >/dev/null
overlay
br_netfilter
EOF
sudo modprobe overlay
sudo modprobe br_netfilter
ok "Kernel modules: overlay, br_netfilter"

cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf >/dev/null
net.bridge.bridge-nf-call-iptables  = 1
net.bridge.bridge-nf-call-ip6tables = 1
net.ipv4.ip_forward                 = 1
EOF
quiet sudo sysctl --system
[[ "$(sysctl -n net.ipv4.ip_forward)" == "1" ]] && ok "sysctl: ip_forward = 1, bridge-nf-call = 1" || die "sysctl not applied"

# =============================================================================
# 2. containerd
# =============================================================================
step "2. Container runtime: containerd"
quiet sudo apt-get update
quiet sudo DEBIAN_FRONTEND=noninteractive apt-get install -y containerd
sudo mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml >/dev/null
sudo sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml
grep -q 'SystemdCgroup = true' /etc/containerd/config.toml || die "Could not set SystemdCgroup = true in /etc/containerd/config.toml"
quiet sudo systemctl restart containerd
quiet sudo systemctl enable containerd
systemctl is-active --quiet containerd || die "containerd is not running"
ok "containerd $(containerd --version | awk '{print $3}') running, SystemdCgroup = true"

# =============================================================================
# 3. kubeadm, kubelet, kubectl
# =============================================================================
step "3. Kubernetes packages (v${K8S_VERSION})"
quiet sudo apt-get install -y apt-transport-https ca-certificates curl gpg
sudo mkdir -p -m 755 /etc/apt/keyrings
curl -fsSL "https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/Release.key" | \
  sudo gpg --dearmor --yes -o /etc/apt/keyrings/kubernetes-apt-keyring.gpg
echo "deb [signed-by=/etc/apt/keyrings/kubernetes-apt-keyring.gpg] https://pkgs.k8s.io/core:/stable:/v${K8S_VERSION}/deb/ /" | \
  sudo tee /etc/apt/sources.list.d/kubernetes.list >/dev/null
quiet sudo apt-get update
quiet sudo DEBIAN_FRONTEND=noninteractive apt-get install -y kubelet kubeadm kubectl cri-tools
quiet sudo apt-mark hold kubelet kubeadm kubectl
quiet sudo systemctl enable kubelet
ok "kubeadm $(kubeadm version -o short), kubectl, kubelet, crictl installed (k8s packages held)"

cat <<EOF | sudo tee /etc/crictl.yaml >/dev/null
runtime-endpoint: unix:///run/containerd/containerd.sock
EOF
ok "crictl -> containerd"

# =============================================================================
# 4. kubeadm init
# =============================================================================
step "4. Create the cluster (kubeadm init) — takes 1–3 minutes"
if [[ -f /etc/kubernetes/admin.conf ]]; then
  warn "Already initialized — skipping kubeadm init"
else
  quiet sudo kubeadm config images pull
  ok "Control-plane images pulled"
  if ! sudo kubeadm init \
        --apiserver-advertise-address="$NODE_IP" \
        --pod-network-cidr="$POD_CIDR" >>"$LOG" 2>&1; then
    tail -30 "$LOG"
    die "kubeadm init failed (see $LOG). Reset with: sudo kubeadm reset -f"
  fi
  ok "Control plane initialized"
fi
mkdir -p "$HOME/.kube"
sudo cp /etc/kubernetes/admin.conf "$HOME/.kube/config"
sudo chown "$(id -u):$(id -g)" "$HOME/.kube/config"
ok "kubeconfig: ~/.kube/config"

# =============================================================================
# 5. Flannel
# =============================================================================
step "5. Pod network: Flannel"
quiet kubectl apply -f "$FLANNEL_URL"
ok "Flannel applied"
kubectl wait --for=condition=Ready node --all --timeout=180s >>"$LOG" 2>&1 \
  && ok "Node is Ready" || die "Node not Ready after 180s (kubectl get pods -n kube-flannel)"

# =============================================================================
# 6. Single node: allow workloads on the control plane
# =============================================================================
step "6. Remove control-plane taint"
kubectl taint nodes --all node-role.kubernetes.io/control-plane- >>"$LOG" 2>&1 || true
ok "Workloads can run on $(hostname)"

kubectl wait --for=condition=Ready pods --all -n kube-system --timeout=180s >>"$LOG" 2>&1 \
  && ok "All kube-system Pods Ready" || warn "Some kube-system Pods not Ready yet"

# =============================================================================
# 7. Smoke test
# =============================================================================
step "7. Smoke test"
quiet kubectl create deployment smoke-test --image=nginx
if kubectl rollout status deployment/smoke-test --timeout=120s >>"$LOG" 2>&1; then
  POD_IP=$(kubectl get pods -l app=smoke-test -o jsonpath='{.items[0].status.podIP}')
  ok "nginx Pod Running with IP $POD_IP"
  curl -s --max-time 5 "http://$POD_IP" | grep -q nginx && ok "HTTP to Pod works" || warn "HTTP to Pod failed"
else
  warn "Smoke test Pod did not start (kubectl describe deploy smoke-test)"
fi
quiet kubectl delete deployment smoke-test

# =============================================================================
# Summary
# =============================================================================
step "Cluster"
kubectl get nodes -o wide
echo
kubectl get pods -A
echo -e "\n${c_grn}Done.${c_off} Warnings: $WARNINGS   Log: $LOG"
echo "Take a VM snapshot now: \"Cluster ready\"."
