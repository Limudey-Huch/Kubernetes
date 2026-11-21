#!/usr/bin/env bash
# =============================================================================
# 03-static-ip.sh — Give the Kubernetes VM a static IP and a hostname
#
# kubeadm writes the node IP into the API server certificate and etcd.
# If the IP changes later (DHCP), the cluster breaks. Run this BEFORE kubeadm.
#
# What it does:
#   1. Detects the main interface, gateway and DNS (no MAC matching)
#   2. Backs up the current netplan files
#   3. Writes /etc/netplan/01-k8s-static.yaml with a static address
#   4. Sets the hostname and /etc/hosts
#   5. Applies the change with an AUTO-ROLLBACK: if you don't confirm within
#      3 minutes, the old network config is restored automatically.
#
# Usage:
#   ./03-static-ip.sh --ip 172.16.71.10/24                    # dry run
#   ./03-static-ip.sh --ip 172.16.71.10/24 --hostname k8s-lab --yes
#   ./03-static-ip.sh --confirm      # run from the NEW IP to keep the change
#
# Options:
#   --ip ADDR/PREFIX   Static address (required). Pick one OUTSIDE the DHCP range.
#   --gw ADDR          Gateway (default: detected)
#   --dns A,B          DNS servers (default: gateway,8.8.8.8)
#   --iface NAME       Interface (default: the one with the default route)
#   --hostname NAME    Hostname to set (default: keep current)
#   --yes              Apply (otherwise dry run)
#   --confirm          Keep the applied config and cancel the auto-rollback
#
# VMware Fusion/Workstation NAT tip: the DHCP range is usually .128–.254,
# so .3–.127 are safe for static addresses (e.g. 172.16.71.10).
# =============================================================================
set -euo pipefail

NETPLAN_FILE=/etc/netplan/01-k8s-static.yaml
BACKUP_DIR=/root/netplan-backup
ROLLBACK_UNIT=k8s-netplan-rollback
ROLLBACK_SECONDS=180

IP_CIDR=""; GW=""; DNS=""; IFACE=""; NEW_HOSTNAME=""; APPLY=false; CONFIRM=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --ip)       IP_CIDR="$2"; shift 2 ;;
    --gw)       GW="$2"; shift 2 ;;
    --dns)      DNS="$2"; shift 2 ;;
    --iface)    IFACE="$2"; shift 2 ;;
    --hostname) NEW_HOSTNAME="$2"; shift 2 ;;
    --yes)      APPLY=true; shift ;;
    --confirm)  CONFIRM=true; shift ;;
    -h|--help)  sed -n '2,32p' "$0"; exit 0 ;;
    *) echo "Unknown option: $1 (see --help)"; exit 1 ;;
  esac
done

c_blue='\033[1;34m'; c_yel='\033[1;33m'; c_grn='\033[1;32m'; c_red='\033[1;31m'; c_off='\033[0m'
step() { echo -e "\n${c_blue}==> $*${c_off}"; }
ok()   { echo -e "   ${c_grn}OK${c_off}  $*"; }
warn() { echo -e "   ${c_yel}!!${c_off}  $*"; }
die()  { echo -e "   ${c_red}ERROR${c_off} $*"; exit 1; }

[[ $EUID -eq 0 ]] && SUDO="" || SUDO="sudo"
$SUDO true || die "This script needs sudo."

# ---- --confirm: keep the new config ----------------------------------------
if $CONFIRM; then
  step "Confirming new network config"
  if systemctl list-timers --all --no-legend | grep -q "$ROLLBACK_UNIT"; then
    $SUDO systemctl stop "${ROLLBACK_UNIT}.timer" 2>/dev/null || true
    ok "Auto-rollback cancelled. The static IP is permanent."
  else
    warn "No pending rollback found (already confirmed, or rollback already ran)."
  fi
  ip -4 -o addr show | awk '$2!="lo"{print "   "$2, $4}'
  exit 0
fi

# ---- 1. Detect current network ---------------------------------------------
step "1. Current network"
[[ -n "$IP_CIDR" ]] || die "--ip is required, e.g. --ip 172.16.71.10/24"
[[ "$IP_CIDR" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || die "--ip must look like 172.16.71.10/24"
NEW_IP="${IP_CIDR%/*}"

[[ -n "$IFACE" ]] || IFACE=$(ip -4 route show default | awk '{print $5; exit}')
[[ -n "$IFACE" ]] || die "Could not detect the main interface. Use --iface."
ip link show "$IFACE" >/dev/null 2>&1 || die "Interface $IFACE does not exist."

[[ -n "$GW" ]] || GW=$(ip -4 route show default dev "$IFACE" | awk '{print $3; exit}')
[[ -n "$GW" ]] || die "Could not detect the gateway. Use --gw."
[[ -n "$DNS" ]] || DNS="${GW},8.8.8.8"

CUR_IP=$(ip -4 -o addr show "$IFACE" | awk '{print $4; exit}')
CUR_DYNAMIC=$(ip -4 addr show "$IFACE" | grep -q ' dynamic ' && echo "yes (DHCP)" || echo "no (static)")
CUR_HOST=$(hostname)
[[ -n "$NEW_HOSTNAME" ]] || NEW_HOSTNAME="$CUR_HOST"

echo "   Interface : $IFACE"
echo "   Current IP: $CUR_IP   dynamic: $CUR_DYNAMIC"
echo "   Gateway   : $GW"
echo "   Hostname  : $CUR_HOST"

# ---- 2. Checks --------------------------------------------------------------
step "2. Checks"
if [[ "$NEW_IP" == "${CUR_IP%/*}" ]]; then
  ok "New IP equals current IP — SSH will stay connected."
elif ping -c1 -W1 "$NEW_IP" >/dev/null 2>&1; then
  die "$NEW_IP answers ping — it is already used by another machine."
else
  ok "$NEW_IP is free (no ping reply)."
  warn "The IP will change: your SSH session will drop. Reconnect to $NEW_IP."
fi
ping -c1 -W2 "$GW" >/dev/null 2>&1 && ok "Gateway $GW reachable." || warn "Gateway $GW did not answer ping."

# ---- 3. New config ----------------------------------------------------------
step "3. New netplan config ($NETPLAN_FILE)"
DNS_YAML=$(echo "$DNS" | sed 's/,/, /g')
NEW_YAML=$(cat <<EOF
# Static IP for the Kubernetes node — written by 03-static-ip.sh
network:
  version: 2
  renderer: networkd
  ethernets:
    ${IFACE}:
      dhcp4: false
      dhcp6: false
      addresses:
        - ${IP_CIDR}
      routes:
        - to: default
          via: ${GW}
      nameservers:
        addresses: [${DNS_YAML}]
EOF
)
echo "$NEW_YAML" | sed 's/^/   /'

step "4. Other changes"
echo "   - Move existing /etc/netplan/*.yaml to $BACKUP_DIR/<timestamp>/"
echo "   - Disable cloud-init network management"
echo "   - Hostname: $CUR_HOST -> $NEW_HOSTNAME"
echo "   - /etc/hosts: '127.0.1.1 $NEW_HOSTNAME' and '$NEW_IP $NEW_HOSTNAME'"
echo "   - Auto-rollback in ${ROLLBACK_SECONDS}s unless you run: $0 --confirm"

if ! $APPLY; then
  echo -e "\n${c_yel}DRY RUN — nothing changed. Re-run with --yes to apply.${c_off}"
  exit 0
fi

# ---- APPLY ------------------------------------------------------------------
step "Applying"
TS=$(date +%Y%m%d-%H%M%S)
BK="$BACKUP_DIR/$TS"
$SUDO mkdir -p "$BK"
$SUDO sh -c "mv /etc/netplan/*.yaml* '$BK'/ 2>/dev/null || true"
ok "Backed up old netplan files to $BK"

echo "$NEW_YAML" | $SUDO tee "$NETPLAN_FILE" >/dev/null
$SUDO chmod 600 "$NETPLAN_FILE"
$SUDO netplan generate || { $SUDO rm -f "$NETPLAN_FILE"; $SUDO sh -c "mv '$BK'/* /etc/netplan/"; die "netplan rejected the config — restored backup."; }
ok "Wrote $NETPLAN_FILE (validated)"

echo 'network: {config: disabled}' | $SUDO tee /etc/cloud/cloud.cfg.d/99-disable-network-config.cfg >/dev/null
ok "cloud-init network config disabled"

if [[ "$NEW_HOSTNAME" != "$CUR_HOST" ]]; then
  $SUDO hostnamectl set-hostname "$NEW_HOSTNAME"
  ok "Hostname set to $NEW_HOSTNAME"
fi
$SUDO sed -i -E "/^127\.0\.1\.1\s/d; /\s${NEW_HOSTNAME}(\s|$)/d" /etc/hosts
$SUDO sed -i "2i 127.0.1.1 ${NEW_HOSTNAME}\n${NEW_IP} ${NEW_HOSTNAME}" /etc/hosts
ok "/etc/hosts updated"

# Auto-rollback: restore old netplan files after N seconds unless --confirm
$SUDO systemctl stop "${ROLLBACK_UNIT}.timer" 2>/dev/null || true
$SUDO systemctl reset-failed "${ROLLBACK_UNIT}.service" 2>/dev/null || true
$SUDO systemd-run --quiet --unit="$ROLLBACK_UNIT" --on-active="$ROLLBACK_SECONDS" \
  /bin/sh -c "rm -f '$NETPLAN_FILE' && cp -a '$BK'/* /etc/netplan/ && netplan apply"
ok "Auto-rollback armed (${ROLLBACK_SECONDS}s)"

echo
echo -e "${c_grn}Applying network config now.${c_off}"
if [[ "$NEW_IP" != "${CUR_IP%/*}" ]]; then
  echo "Your SSH session will disconnect. Within ${ROLLBACK_SECONDS} seconds:"
  echo "    ssh $(whoami)@${NEW_IP}"
  echo "    ./03-static-ip.sh --confirm"
else
  echo "Then run:  $0 --confirm"
fi
# Apply in the background so this script can finish printing before SSH drops
$SUDO systemd-run --quiet --on-active=2 /usr/sbin/netplan apply
