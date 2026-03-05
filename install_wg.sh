#!/usr/bin/env bash
set -euo pipefail

# install_wg.sh
# WireGuard installer for Ubuntu 22.04 / Debian-like systems.
# Focus: wg-quick deployment with safer defaults and MTU mitigation.

SERVER_PORT="51820"
WG_SUBNET="10.77.0.0/24"
WG_INTERFACE="wg0"
WG_DIR="/etc/wireguard"
WG_CONF="${WG_DIR}/${WG_INTERFACE}.conf"
SYSCTL_FILE="/etc/sysctl.d/99-wireguard-forwarding.conf"

usage() {
  cat <<USAGE
Usage:
  sudo ./install_wg.sh [--port PORT] [--subnet CIDR] [--iface IFACE]

Options:
  --port PORT       WireGuard UDP listen port (default: 51820)
  --subnet CIDR     WireGuard subnet (default: 10.77.0.0/24)
  --iface IFACE     WireGuard interface name (default: wg0)
  -h, --help        Show this help

Examples:
  sudo ./install_wg.sh
  sudo ./install_wg.sh --port 51820 --subnet 10.77.0.0/24 --iface wg0
USAGE
}

require_root() {
  if [[ "${EUID}" -ne 0 ]]; then
    echo "[ERROR] Please run as root: sudo $0"
    exit 1
  fi
}

validate_port() {
  if ! [[ "${SERVER_PORT}" =~ ^[0-9]+$ ]] || (( SERVER_PORT < 1 || SERVER_PORT > 65535 )); then
    echo "[ERROR] Invalid port: ${SERVER_PORT}. Must be 1..65535"
    exit 1
  fi
}

validate_subnet() {
  if ! [[ "${WG_SUBNET}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/([0-9]|[1-2][0-9]|3[0-2])$ ]]; then
    echo "[ERROR] Invalid subnet format: ${WG_SUBNET}"
    echo "        Expected example: 10.77.0.0/24"
    exit 1
  fi

  local base cidr o1 o2 o3 o4
  base="${WG_SUBNET%%/*}"
  cidr="${WG_SUBNET##*/}"
  IFS='.' read -r o1 o2 o3 o4 <<< "${base}"

  for oct in "$o1" "$o2" "$o3" "$o4"; do
    if (( oct < 0 || oct > 255 )); then
      echo "[ERROR] Invalid subnet octet in ${WG_SUBNET}"
      exit 1
    fi
  done

  if (( cidr < 24 || cidr > 30 )); then
    echo "[WARN] CIDR /${cidr} may not be ideal for simple VPN peer addressing. Recommended: /24"
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --port)
        SERVER_PORT="${2:-}"
        shift 2
        ;;
      --subnet)
        WG_SUBNET="${2:-}"
        shift 2
        ;;
      --iface)
        WG_INTERFACE="${2:-}"
        WG_CONF="${WG_DIR}/${WG_INTERFACE}.conf"
        shift 2
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        echo "[ERROR] Unknown argument: $1"
        usage
        exit 1
        ;;
    esac
  done
}

require_commands() {
  local needed=(ip awk sed systemctl modprobe wg)
  local missing=()

  for c in "${needed[@]}"; do
    if ! command -v "$c" >/dev/null 2>&1; then
      missing+=("$c")
    fi
  done

  if (( ${#missing[@]} > 0 )); then
    echo "[INFO] Missing base tools detected: ${missing[*]}"
    echo "[INFO] Installing required packages..."
  fi
}

install_packages() {
  echo "[INFO] Installing WireGuard packages for Ubuntu 22.04..."
  export DEBIAN_FRONTEND=noninteractive
  apt-get update -y
  # iptables is intentionally installed for explicit wg-quick PostUp/PostDown rules.
  apt-get install -y wireguard wireguard-tools iproute2 iptables qrencode
}

check_os() {
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    echo "[INFO] Detected OS: ${PRETTY_NAME:-unknown}"
    if [[ "${ID:-}" != "ubuntu" ]]; then
      echo "[WARN] Script optimized for Ubuntu 22.04, continuing on ${ID:-unknown}."
    fi
  else
    echo "[WARN] Could not read /etc/os-release"
  fi
}

check_kernel_module() {
  if ! modprobe wireguard 2>/dev/null; then
    echo "[WARN] Could not load wireguard kernel module."
    echo "       Verify kernel support (CONFIG_WIREGUARD) on your board."
  fi
}

derive_server_address() {
  local base cidr o1 o2 o3
  base="${WG_SUBNET%%/*}"
  cidr="${WG_SUBNET##*/}"
  IFS='.' read -r o1 o2 o3 _ <<< "${base}"
  printf "%s.%s.%s.1/%s" "$o1" "$o2" "$o3" "$cidr"
}

detect_default_iface() {
  ip -4 route show default 2>/dev/null | awk 'NR==1 {print $5}'
}

calculate_mtu() {
  local default_iface default_mtu wg_mtu

  default_iface="$(detect_default_iface || true)"
  default_mtu=""

  if [[ -n "${default_iface}" ]]; then
    default_mtu="$(ip link show dev "${default_iface}" | awk '/mtu/ {for(i=1;i<=NF;i++) if($i=="mtu") print $(i+1)}' | head -n1)"
  fi

  if [[ -n "${default_mtu}" && "${default_mtu}" =~ ^[0-9]+$ ]]; then
    wg_mtu="$((default_mtu - 80))"
    if (( wg_mtu < 1280 )); then
      wg_mtu=1280
    fi
  else
    wg_mtu=1280
  fi

  echo "${wg_mtu}"
}

setup_keys() {
  local priv_file pub_file
  priv_file="${WG_DIR}/server_private.key"
  pub_file="${WG_DIR}/server_public.key"

  mkdir -p "${WG_DIR}"
  chmod 700 "${WG_DIR}"

  if [[ ! -s "${priv_file}" ]]; then
    umask 077
    wg genkey | tee "${priv_file}" | wg pubkey > "${pub_file}"
  elif [[ ! -s "${pub_file}" ]]; then
    wg pubkey < "${priv_file}" > "${pub_file}"
  fi

  chmod 600 "${priv_file}" "${pub_file}"
}

write_config() {
  local server_addr="$1"
  local wg_mtu="$2"
  local public_iface="$3"
  local priv_file="${WG_DIR}/server_private.key"

  # Keep existing config as backup if present.
  if [[ -f "${WG_CONF}" ]]; then
    cp -a "${WG_CONF}" "${WG_CONF}.bak.$(date +%Y%m%d%H%M%S)"
  fi

  cat > "${WG_CONF}" <<CONF
[Interface]
Address = ${server_addr}
ListenPort = ${SERVER_PORT}
PrivateKey = $(cat "${priv_file}")
MTU = ${wg_mtu}

PostUp = iptables -A FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -A FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -A POSTROUTING -o ${public_iface} -j MASQUERADE
PostDown = iptables -D FORWARD -i ${WG_INTERFACE} -j ACCEPT; iptables -D FORWARD -o ${WG_INTERFACE} -j ACCEPT; iptables -t nat -D POSTROUTING -o ${public_iface} -j MASQUERADE
CONF

  chmod 600 "${WG_CONF}"
}

enable_forwarding() {
  cat > "${SYSCTL_FILE}" <<'SYSCTL'
net.ipv4.ip_forward=1
SYSCTL
  sysctl --system >/dev/null
}

start_service() {
  systemctl daemon-reload
  systemctl enable --now "wg-quick@${WG_INTERFACE}"
}

main() {
  parse_args "$@"
  require_root
  check_os
  validate_port
  validate_subnet
  require_commands
  install_packages
  check_kernel_module
  setup_keys

  local server_addr default_iface public_iface wg_mtu pub_key
  server_addr="$(derive_server_address)"
  default_iface="$(detect_default_iface || true)"
  public_iface="${default_iface:-eth0}"
  wg_mtu="$(calculate_mtu)"

  echo "[INFO] Using WireGuard MTU: ${wg_mtu}"
  echo "[INFO] Public interface for NAT: ${public_iface}"

  write_config "${server_addr}" "${wg_mtu}" "${public_iface}"
  enable_forwarding
  start_service

  pub_key="$(cat "${WG_DIR}/server_public.key")"
  cat <<DONE

[SUCCESS] WireGuard installed and configured.
  OS         : Ubuntu 22.04 compatible script
  Interface  : ${WG_INTERFACE}
  Address    : ${server_addr}
  ListenPort : ${SERVER_PORT}
  MTU        : ${wg_mtu}
  Public key : ${pub_key}

Next steps:
1) Add a peer:
   wg set ${WG_INTERFACE} peer <PEER_PUBKEY> allowed-ips <PEER_VPN_IP>/32
2) Persist runtime config:
   wg-quick save ${WG_INTERFACE}
3) Check tunnel status:
   wg show
DONE
}

main "$@"
