#!/usr/bin/env bash
# =============================================================================
# 01-reset-vm.sh — Clean an Ubuntu VM before installing Kubernetes (kubeadm)
#
# Removes anything that conflicts with a fresh kubeadm install:
#   - Previous Kubernetes install (kubeadm reset, packages, config, data)
#   - Docker Engine + containerd.io (and all containers, images, volumes)
#   - Extra services that use ports/resources (Jenkins, etc.)
#   - Swap
#
# Does NOT touch: SSH, networking (netplan/networkd), DNS, time sync,
# VM tools, users, or your home directory files (except ~/.kube).
#
# Usage:
#   ./01-reset-vm.sh            # show what WOULD be removed (dry run)
#   ./01-reset-vm.sh --yes      # actually remove it
#
# Take a VM snapshot before running with --yes.
# =============================================================================
set -uo pipefail

APPLY=false
[[ "${1:-}" == "--yes" ]] && APPLY=true

# ---- What to clean ----------------------------------------------------------
# Extra services to stop, disable and purge if present (add your own here)
EXTRA_SERVICES=(jenkins apache2 nginx mysql postgresql)
EXTRA_PACKAGES=(jenkins apache2 nginx mysql-server postgresql)

# Container / Kubernetes packages that conflict with a clean install
CONTAINER_PACKAGES=(
  docker-ce docker-ce-cli docker-ce-rootless-extras
  docker-buildx-plugin docker-compose-plugin docker-model-plugin
  docker.io docker-compose docker-doc podman-docker
  containerd containerd.io runc
)
K8S_PACKAGES=(kubeadm kubelet kubectl kubernetes-cni cri-tools)

# Data and config directories to delete
CLEAN_DIRS=(
  /etc/kubernetes /var/lib/etcd /var/lib/kubelet /etc/cni /var/lib/cni /opt/cni
  /var/lib/docker /etc/docker /var/lib/containerd /etc/containerd /run/containerd
  /etc/crictl.yaml
)
# Old apt repos for Docker / Kubernetes
CLEAN_APT_FILES=(
  /etc/apt/sources.list.d/docker.list /etc/apt/sources.list.d/docker.sources
  /etc/apt/sources.list.d/kubernetes.list
  /etc/apt/keyrings/docker.asc /etc/apt/keyrings/docker.gpg
  /etc/apt/keyrings/kubernetes-apt-keyring.gpg
)

# ---- Helpers ----------------------------------------------------------------
c_blue='\033[1;34m'; c_yel='\033[1;33m'; c_grn='\033[1;32m'; c_off='\033[0m'
step() { echo -e "\n${c_blue}==> $*${c_off}"; }
plan() { echo -e "   ${c_yel}[would]${c_off} $*"; }
did()  { echo -e "   ${c_grn}[done]${c_off}  $*"; }

run() {  # run "description" cmd args...
  local desc="$1"; shift
  if $APPLY; then "$@" >/dev/null 2>&1; did "$desc"; else plan "$desc"; fi
}

installed_pkgs() {  # print which of the given packages are installed
  for p in "$@"; do
    dpkg -s "$p" >/dev/null 2>&1 && echo "$p"
  done
}

[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
$SUDO true || { echo "This script needs sudo."; exit 1; }

$APPLY && echo "MODE: APPLY — changes will be made" \
       || echo "MODE: DRY RUN — nothing will change. Run with --yes to apply."

# ---- 1. Previous Kubernetes -------------------------------------------------
step "1. Previous Kubernetes install"
if command -v kubeadm >/dev/null 2>&1; then
  run "kubeadm reset -f" $SUDO kubeadm reset -f
else
  echo "   kubeadm not found — skipping reset"
fi
mapfile -t k8s_found < <(installed_pkgs "${K8S_PACKAGES[@]}")
if (( ${#k8s_found[@]} )); then
  run "apt-mark unhold ${k8s_found[*]}" $SUDO apt-mark unhold "${k8s_found[@]}"
  run "purge ${k8s_found[*]}" $SUDO apt-get purge -y --allow-change-held-packages "${k8s_found[@]}"
else
  echo "   no Kubernetes packages installed"
fi
if [[ -d "$HOME/.kube" ]]; then run "remove ~/.kube" rm -rf "$HOME/.kube"; fi

# ---- 2. Extra services ------------------------------------------------------
step "2. Extra services (${EXTRA_SERVICES[*]})"
for s in "${EXTRA_SERVICES[@]}"; do
  if systemctl list-unit-files "${s}.service" --no-legend 2>/dev/null | grep -q .; then
    run "stop + disable ${s}" $SUDO systemctl disable --now "$s"
  fi
done
mapfile -t extra_found < <(installed_pkgs "${EXTRA_PACKAGES[@]}")
if (( ${#extra_found[@]} )); then
  run "purge ${extra_found[*]}" $SUDO apt-get purge -y "${extra_found[@]}"
  for p in "${extra_found[@]}"; do
    [[ -d /var/lib/$p ]] && run "remove /var/lib/$p" $SUDO rm -rf "/var/lib/$p"
  done
else
  echo "   none installed"
fi

# ---- 3. Docker and containerd ----------------------------------------------
step "3. Docker / containerd"
if command -v docker >/dev/null 2>&1 && $SUDO docker info >/dev/null 2>&1; then
  n_cont=$($SUDO docker ps -aq | wc -l)
  n_img=$($SUDO docker images -q | sort -u | wc -l)
  n_vol=$($SUDO docker volume ls -q | wc -l)
  echo "   found: ${n_cont} containers, ${n_img} images, ${n_vol} volumes"
  run "remove all containers, images, volumes, networks" \
      $SUDO docker system prune -af --volumes
fi
for s in docker.socket docker.service containerd.service; do
  if systemctl cat "$s" >/dev/null 2>&1; then
    run "stop + disable $s" $SUDO systemctl disable --now "$s"
  fi
done
mapfile -t cont_found < <(installed_pkgs "${CONTAINER_PACKAGES[@]}")
if (( ${#cont_found[@]} )); then
  run "purge ${cont_found[*]}" $SUDO apt-get purge -y "${cont_found[@]}"
else
  echo "   no container packages installed"
fi
if getent group docker >/dev/null; then
  run "remove 'docker' group" $SUDO groupdel docker
fi

# ---- 4. Leftover data, config and apt repos --------------------------------
step "4. Leftover directories and apt repos"
for d in "${CLEAN_DIRS[@]}" "${CLEAN_APT_FILES[@]}"; do
  [[ -e "$d" ]] && run "remove $d" $SUDO rm -rf "$d"
done

# Leftover virtual network interfaces (CNI / Docker)
for ifc in cni0 flannel.1 docker0 $(ip -o link show | awk -F': ' '{print $2}' | grep -E '^(br-|veth|cali|vxlan)' | cut -d@ -f1); do
  ip link show "$ifc" >/dev/null 2>&1 && run "delete interface $ifc" $SUDO ip link delete "$ifc"
done

# iptables rules left by Docker / kube-proxy
if command -v iptables >/dev/null 2>&1; then
  run "flush iptables rules (filter, nat, mangle)" \
      bash -c "$SUDO iptables -F && $SUDO iptables -t nat -F && $SUDO iptables -t mangle -F && $SUDO iptables -X"
fi

# ---- 5. Swap ----------------------------------------------------------------
step "5. Swap"
if swapon --show | grep -q .; then
  run "swapoff -a" $SUDO swapoff -a
else
  echo "   swap is already off"
fi
if grep -Eq '^[^#].*\sswap\s' /etc/fstab; then
  run "comment swap lines in /etc/fstab" $SUDO sed -i.bak -E '/^[^#].*\sswap\s/ s/^/#/' /etc/fstab
fi

# ---- 6. apt cleanup ---------------------------------------------------------
step "6. apt cleanup"
run "apt-get autoremove --purge" $SUDO apt-get autoremove -y --purge
run "apt-get update" $SUDO apt-get update

# ---- Summary ----------------------------------------------------------------
step "Result"
if $APPLY; then
  echo "   Running services now:"
  systemctl list-units --type=service --state=running --no-legend | awk '{print "     - "$1}'
  echo
  echo "   Listening ports:"
  $SUDO ss -ltnp | awk 'NR>1{print "     - "$4}'
  echo
  echo "Done. A reboot is recommended:  sudo reboot"
else
  echo "   Dry run finished. Re-run with --yes to apply."
fi
