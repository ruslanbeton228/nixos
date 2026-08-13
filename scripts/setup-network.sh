#!/usr/bin/env bash

# Configures temporary static IPv4 networking in a NixOS installer.
# This file is standalone and does not invoke Nix or download packages.

set -o errexit
set -o nounset
set -o pipefail

interface=""
ip_address=""
gateway=""
dns_server=""

# Prints an informational message.
log() {
  printf '\n==> %s\n' "$*"
}

# Prints an error and exits.
die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Reads an editable line using Readline when attached to a terminal.
read_input() {
  local variable_name="$1"
  local message="$2"
  local response=""

  if [[ -t 0 ]]; then
    IFS= read -e -r -p "${message}" response
  else
    IFS= read -r -p "${message}" response
  fi
  printf -v "${variable_name}" '%s' "${response}"
}

# Reads an editable value prefilled with a default.
prompt_default() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local response=""

  if [[ -t 0 ]]; then
    IFS= read -e -r -i "${default_value}" \
      -p "${message}: " response
  else
    IFS= read -r -p "${message} [${default_value}]: " response
    response="${response:-${default_value}}"
  fi
  printf -v "${variable_name}" '%s' "${response}"
}

# Asks a yes or no question.
confirm() {
  local message="$1"
  local default_answer="${2:-no}"
  local hint="[y/N]"
  local response=""

  if [[ "${default_answer}" == "yes" ]]; then
    hint="[Y/n]"
  fi

  read_input response "${message} ${hint}: "
  response="${response,,}"

  if [[ -z "${response}" ]]; then
    [[ "${default_answer}" == "yes" ]]
    return
  fi

  [[ "${response}" == "y" || "${response}" == "yes" ]]
}

# Verifies that the script has administrative privileges.
require_root() {
  ((EUID == 0)) || die "run this script as root"
}

# Verifies the minimal commands expected on a NixOS installer image.
check_dependencies() {
  local command=""

  for command in ip ping; do
    command -v "${command}" >/dev/null || {
      die "required command was not found: ${command}"
    }
  done
}

# Returns success when the value is a valid IPv4 address.
is_ipv4() {
  local value="$1"
  local octet=""
  local -a octets=()

  IFS='.' read -r -a octets <<<"${value}"
  ((${#octets[@]} == 4)) || return 1

  for octet in "${octets[@]}"; do
    [[ "${octet}" =~ ^[0-9]+$ ]] || return 1
    ((${#octet} <= 3)) || return 1
    ((10#${octet} <= 255)) || return 1
  done
}

# Returns success for an IPv4 address with a CIDR prefix.
is_ipv4_cidr() {
  local value="$1"
  local address="${value%/*}"
  local prefix="${value##*/}"

  [[ "${value}" == */* && "${address}" != "${value}" ]] || return 1
  [[ "${prefix}" != */* ]] || return 1
  is_ipv4 "${address}" || return 1
  [[ "${prefix}" =~ ^[0-9]{1,2}$ ]] || return 1
  ((10#${prefix} <= 32))
}

# Lists usable network interfaces and asks the user to choose one.
select_interface() {
  local -a interfaces=()
  local interface_name=""
  local selection=""
  local index=0

  while read -r interface_name _; do
    interface_name="${interface_name%%@*}"
    [[ "${interface_name}" == "lo" ]] || {
      interfaces+=("${interface_name}")
    }
  done < <(ip -brief link show)
  ((${#interfaces[@]} > 0)) || die "no network interfaces were found"

  log "Available network interfaces"
  for index in "${!interfaces[@]}"; do
    printf '%d) ' "$((index + 1))"
    ip -brief link show dev "${interfaces[index]}"
  done

  while true; do
    read_input selection "Select the interface by number: "
    if [[ "${selection}" =~ ^[0-9]+$ ]] \
      && ((selection >= 1 && selection <= ${#interfaces[@]})); then
      interface="${interfaces[selection - 1]}"
      return
    fi
    printf 'Please select a number from the list.\n'
  done
}

# Reads and validates an IPv4 address with a CIDR prefix.
prompt_ipv4_cidr() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local response=""

  while true; do
    prompt_default response "${message}" "${default_value}"
    if is_ipv4_cidr "${response}"; then
      printf -v "${variable_name}" '%s' "${response}"
      return
    fi
    printf 'Enter an IPv4 address with a prefix, for example /24.\n'
  done
}

# Reads and validates one IPv4 address.
prompt_ipv4() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local response=""

  while true; do
    prompt_default response "${message}" "${default_value}"
    if is_ipv4 "${response}"; then
      printf -v "${variable_name}" '%s' "${response}"
      return
    fi
    printf 'Enter a valid IPv4 address.\n'
  done
}

# Reads the address, gateway and DNS resolver.
configure_network() {
  local detected_address=""
  local detected_gateway=""
  local address=""

  while read -r _ _ _ address _; do
    detected_address="${address}"
    break
  done < <(ip -4 -o address show dev "${interface}")
  while read -r _ _ detected_gateway _; do
    break
  done < <(ip -4 route show default dev "${interface}")

  prompt_ipv4_cidr ip_address "IPv4 address with CIDR prefix" \
    "${detected_address:-192.168.1.100/24}"

  prompt_ipv4 gateway "Default gateway" \
    "${detected_gateway:-192.168.1.1}"
  prompt_ipv4 dns_server "DNS resolver" "1.1.1.1"
}

# Prints the proposed temporary network configuration.
show_plan() {
  log "Network plan"
  printf 'Interface:       %s\n' "${interface}"
  printf 'IPv4 address:    %s\n' "${ip_address}"
  printf 'Default gateway: %s\n' "${gateway}"
  printf 'DNS resolver:    %s\n' "${dns_server}"
}

# Configures DNS through systemd-resolved or resolv.conf.
configure_resolver() {
  if command -v resolvectl >/dev/null \
    && resolvectl status >/dev/null 2>&1; then
    resolvectl dns "${interface}" "${dns_server}"
    resolvectl domain "${interface}" "~."
    return
  fi

  if [[ -L /etc/resolv.conf && ! -e /etc/resolv.conf ]]; then
    unlink /etc/resolv.conf
  fi
  printf 'nameserver %s\n' "${dns_server}" >/etc/resolv.conf
}

# Applies the selected static network configuration.
apply_network() {
  log "Applying network configuration"
  ip link set dev "${interface}" up
  ip -4 address flush dev "${interface}"
  ip -4 route flush dev "${interface}"
  ip address add "${ip_address}" dev "${interface}"
  ip route add default via "${gateway}" dev "${interface}"
  configure_resolver
}

# Verifies local configuration, connectivity and name resolution.
check_network() {
  local dns_failed="false"
  local failed="false"

  log "Checking network"
  ip -4 address show dev "${interface}"
  ip -4 route show dev "${interface}"

  if ping -c 1 -W 3 "${gateway}" >/dev/null; then
    printf 'Gateway is reachable.\n'
  else
    printf 'Gateway is not reachable.\n' >&2
    failed="true"
  fi

  if ping -c 1 -W 3 1.1.1.1 >/dev/null; then
    printf 'External IPv4 connectivity works.\n'
  else
    printf 'External IPv4 connectivity check failed.\n' >&2
    failed="true"
  fi

  if command -v getent >/dev/null; then
    getent ahostsv4 nixos.org >/dev/null || dns_failed="true"
  elif ! ping -c 1 -W 3 nixos.org >/dev/null; then
    dns_failed="true"
  fi

  if [[ "${dns_failed}" == "false" ]]; then
    printf 'DNS resolution works.\n'
  else
    printf 'DNS resolution failed.\n' >&2
    failed="true"
  fi

  [[ "${failed}" == "false" ]] || die "network checks failed"
  log "Network is ready"
}

# Coordinates the interactive network setup workflow.
main() {
  require_root
  check_dependencies
  select_interface
  configure_network
  show_plan
  confirm "Apply this temporary network configuration?" "no" || {
    die "network setup cancelled"
  }
  apply_network
  check_network
}

main "$@"
