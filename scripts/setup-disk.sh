#!/usr/bin/env bash

# Prepares and optionally mounts storage for a NixOS installation.
# No NixOS installation is started by this script.

set -o errexit
set -o nounset
set -o pipefail

readonly MIB=$((1024 * 1024))
readonly GIB=$((1024 * 1024 * 1024))

target_disk=""
install_mode=""
partition_table=""
use_lvm=""
use_home=""
boot_size_mib=""
root_size_gib=""
home_size_gib=""
swap_size_gib=""
boot_label=""
root_label=""
home_label=""
swap_label=""
volume_group=""
boot_device=""
root_device=""
home_device=""
swap_device=""
boot_mount_point=""
boot_file_system=""
format_boot="false"
format_root="false"
format_home="false"
format_swap="false"
mount_after_setup="false"

# Prints an informational message.
log() {
  printf '\n==> %s\n' "$*"
}

# Prints an error and exits.
die() {
  printf 'Error: %s\n' "$*" >&2
  exit 1
}

# Reads a value and applies a default when the response is empty.
prompt_default() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local response=""

  read -r -p "${message} [${default_value}]: " response
  printf -v "${variable_name}" '%s' "${response:-${default_value}}"
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

  read -r -p "${message} ${hint}: " response
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

# Returns the partition path for a disk and partition number.
partition_path() {
  local disk="$1"
  local number="$2"

  if [[ "${disk}" =~ [0-9]$ ]]; then
    printf '%sp%s\n' "${disk}" "${number}"
  else
    printf '%s%s\n' "${disk}" "${number}"
  fi
}

# Waits until the kernel exposes a new block device.
wait_for_device() {
  local device="$1"
  local attempt=0

  for ((attempt = 0; attempt < 20; attempt++)); do
    [[ -b "${device}" ]] && return
    sleep 1
  done
  die "block device did not appear: ${device}"
}

# Lists physical disks and asks the user to choose one.
select_target_disk() {
  local -a disks=()
  local selection=""
  local index=0

  mapfile -t disks < <(
    lsblk --nodeps --noheadings --paths --output NAME,TYPE \
      | awk '$2 == "disk" {print $1}'
  )
  ((${#disks[@]} > 0)) || die "no disks were found"

  log "Available disks"
  for index in "${!disks[@]}"; do
    printf '%d) ' "$((index + 1))"
    lsblk --nodeps --noheadings --paths \
      --output NAME,SIZE,MODEL,TRAN "${disks[index]}"
  done

  while true; do
    read -r -p "Select the target disk by number: " selection
    if [[ "${selection}" =~ ^[0-9]+$ ]] \
      && ((selection >= 1 && selection <= ${#disks[@]})); then
      target_disk="${disks[selection - 1]}"
      break
    fi
    printf 'Please select a number from the list.\n'
  done

  log "Current layout on ${target_disk}"
  lsblk --paths --output \
    NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${target_disk}"
}

# Selects a fresh layout or reuse of existing filesystems.
select_install_mode() {
  local selection=""

  printf '\n1) Fresh layout; erase and repartition the disk\n'
  printf '2) Reuse existing filesystems for reinstallation\n'
  while true; do
    read -r -p "Select the preparation mode [1]: " selection
    case "${selection:-1}" in
      1)
        install_mode="fresh"
        return
        ;;
      2)
        install_mode="reuse"
        return
        ;;
      *) printf 'Please select 1 or 2.\n' ;;
    esac
  done
}

# Reads and validates a positive integer.
prompt_positive_integer() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local response=""

  while true; do
    prompt_default response "${message}" "${default_value}"
    if [[ "${response}" =~ ^[0-9]+$ ]] && ((response > 0)); then
      printf -v "${variable_name}" '%s' "${response}"
      return
    fi
    printf 'Enter a positive whole number.\n'
  done
}

# Reads a size where zero means all available space.
prompt_size_or_remaining() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local response=""

  while true; do
    prompt_default response "${message}" "${default_value}"
    if [[ "${response}" =~ ^[0-9]+$ ]]; then
      printf -v "${variable_name}" '%s' "${response}"
      return
    fi
    printf 'Enter zero or a positive whole number.\n'
  done
}

# Reads a filesystem label with portable characters.
prompt_label() {
  local variable_name="$1"
  local message="$2"
  local default_value="$3"
  local maximum_length="$4"
  local response=""

  while true; do
    prompt_default response "${message}" "${default_value}"
    if [[ "${response}" =~ ^[A-Za-z0-9._-]+$ ]] \
      && ((${#response} <= maximum_length)); then
      printf -v "${variable_name}" '%s' "${response}"
      return
    fi
    printf 'Use at most %s portable label characters.\n' \
      "${maximum_length}"
  done
}

# Reads a valid LVM volume group name.
prompt_volume_group() {
  local response=""

  while true; do
    prompt_default response "LVM volume group name" "vg0"
    if [[ "${response}" =~ ^[A-Za-z0-9+_.-]+$ ]]; then
      volume_group="${response}"
      return
    fi
    printf 'Use letters, numbers, plus, dot, dash or underscore.\n'
  done
}

# Reads a new partition table and filesystem layout.
configure_fresh_layout() {
  local selection=""

  printf '\n1) GPT with an EFI System Partition; recommended\n'
  printf '2) MBR without a separate boot partition; legacy BIOS\n'
  while true; do
    read -r -p "Select the partition table [1]: " selection
    case "${selection:-1}" in
      1)
        partition_table="gpt"
        boot_mount_point="/boot/efi"
        boot_file_system="vfat"
        break
        ;;
      2)
        partition_table="mbr"
        break
        ;;
      *) printf 'Please select 1 or 2.\n' ;;
    esac
  done

  if confirm "Use LVM for root, home and swap?" "yes"; then
    use_lvm="true"
    prompt_volume_group
    vgs "${volume_group}" >/dev/null 2>&1 && {
      die "LVM volume group already exists: ${volume_group}"
    }
  else
    use_lvm="false"
  fi

  if confirm "Create a separate home filesystem?" "yes"; then
    use_home="true"
  else
    use_home="false"
  fi

  if [[ "${partition_table}" == "gpt" ]]; then
    prompt_positive_integer boot_size_mib "Boot size in MiB" "512"
    prompt_label boot_label "Boot filesystem label" "EFI" "11"
  fi
  if [[ "${use_home}" == "true" ]]; then
    prompt_positive_integer root_size_gib "Root size in GiB" "64"
    prompt_size_or_remaining home_size_gib \
      "Home size in GiB; use 0 for remaining space" "0"
  else
    prompt_size_or_remaining root_size_gib \
      "Root size in GiB; use 0 for remaining space" "0"
    home_size_gib=0
  fi
  prompt_positive_integer swap_size_gib "Swap size in GiB" "8"
  prompt_label root_label "Root filesystem label" "root" "16"
  if [[ "${use_home}" == "true" ]]; then
    prompt_label home_label "Home filesystem label" "home" "16"
  fi
  prompt_label swap_label "Swap label" "swap" "15"

  validate_fresh_sizes
  [[ "${partition_table}" == "gpt" ]] && format_boot="true"
  format_root="true"
  [[ "${use_home}" == "false" ]] || format_home="true"
  format_swap="true"
}

# Ensures that fixed sizes fit on the selected disk.
validate_fresh_sizes() {
  local disk_bytes=0
  local required_bytes=0

  disk_bytes="$(blockdev --getsize64 "${target_disk}")"
  required_bytes=$((swap_size_gib * GIB + 8 * MIB))
  required_bytes=$((required_bytes + root_size_gib * GIB))
  if [[ "${use_home}" == "true" ]]; then
    required_bytes=$((required_bytes + home_size_gib * GIB))
  fi
  if [[ "${partition_table}" == "gpt" ]]; then
    required_bytes=$((required_bytes + boot_size_mib * MIB))
  fi

  ((required_bytes < disk_bytes)) || {
    die "the requested fixed sizes do not fit on ${target_disk}"
  }
}

# Lists reusable partitions and logical volumes below the target disk.
list_reusable_devices() {
  lsblk --raw --paths --noheadings \
    --output NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS "${target_disk}" \
    | awk '$3 == "part" || $3 == "lvm" || $3 == "crypt"'
}

# Selects one existing device from the target disk.
select_existing_device() {
  local variable_name="$1"
  local role="$2"
  local optional="$3"
  local -a devices=()
  local selection=""
  local index=0

  mapfile -t devices < <(list_reusable_devices | awk '{print $1}')
  ((${#devices[@]} > 0)) || die "no reusable devices were found"

  log "Existing devices for ${role}"
  list_reusable_devices
  [[ "${optional}" == "true" ]] \
    && printf '0) Do not configure %s\n' "${role}"
  for index in "${!devices[@]}"; do
    printf '%d) %s\n' "$((index + 1))" "${devices[index]}"
  done

  while true; do
    read -r -p "Select the device for ${role}: " selection
    if [[ "${optional}" == "true" && "${selection}" == "0" ]]; then
      printf -v "${variable_name}" '%s' ""
      return
    fi
    if [[ "${selection}" =~ ^[0-9]+$ ]] \
      && ((selection >= 1 && selection <= ${#devices[@]})); then
      printf -v "${variable_name}" '%s' \
        "${devices[selection - 1]}"
      return
    fi
    printf 'Please select a valid number.\n'
  done
}

# Ensures that each filesystem role uses a different device.
validate_existing_devices() {
  local -a devices=(
    "${boot_device}"
    "${root_device}"
    "${home_device}"
    "${swap_device}"
  )
  local first=0
  local second=0

  for first in "${!devices[@]}"; do
    [[ -n "${devices[first]}" ]] || continue
    for ((second = first + 1; second < ${#devices[@]}; second++)); do
      [[ "${devices[first]}" != "${devices[second]}" ]] || {
        die "a device cannot be selected for multiple roles"
      }
    done
  done
}

# Reads formatting decisions for an existing layout.
configure_existing_layout() {
  local detected_file_system=""

  select_existing_device boot_device "boot" "true"
  select_existing_device root_device "root" "false"
  select_existing_device home_device "home" "true"
  select_existing_device swap_device "swap" "true"
  validate_existing_devices

  if [[ -n "${boot_device}" ]]; then
    detected_file_system="$(
      blkid -s TYPE -o value "${boot_device}" || true
    )"
    if [[ "${detected_file_system}" == "vfat" ]]; then
      boot_file_system="vfat"
      boot_mount_point="/boot/efi"
    else
      boot_file_system="ext4"
      boot_mount_point="/boot"
    fi
    confirm "Format ${boot_device}?" "no" && format_boot="true"
  fi

  confirm "Format ${root_device}?" "yes" && format_root="true"
  if [[ -n "${home_device}" ]]; then
    confirm "Format ${home_device}? Existing home data will be lost." \
      "no" && format_home="true"
  fi
  if [[ -n "${swap_device}" ]]; then
    confirm "Recreate swap on ${swap_device}?" "no" \
      && format_swap="true"
  fi

  if [[ "${format_boot}" == "true" ]]; then
    if [[ "${boot_file_system}" == "vfat" ]]; then
      prompt_label boot_label "Boot filesystem label" "EFI" "11"
    else
      prompt_label boot_label "Boot filesystem label" "boot" "16"
    fi
  fi
  if [[ "${format_root}" == "true" ]]; then
    prompt_label root_label "Root filesystem label" "root" "16"
  fi
  if [[ "${format_home}" == "true" ]]; then
    prompt_label home_label "Home filesystem label" "home" "16"
  fi
  if [[ "${format_swap}" == "true" ]]; then
    prompt_label swap_label "Swap label" "swap" "15"
  fi
}

# Asks whether prepared filesystems should be mounted below /mnt.
configure_mounting() {
  if confirm "Mount the prepared filesystems below /mnt?" "yes"; then
    mount_after_setup="true"
  fi
}

# Prints the complete storage preparation plan.
show_plan() {
  log "Storage plan"
  printf 'Mode:             %s\n' "${install_mode}"
  printf 'Target disk:      %s\n' "${target_disk}"

  if [[ "${install_mode}" == "fresh" ]]; then
    printf 'Partition table:  %s\n' "${partition_table}"
    if [[ "${partition_table}" == "gpt" ]]; then
      printf 'Boot:             %s MiB, vfat, label %s\n' \
        "${boot_size_mib}" "${boot_label}"
    else
      printf 'Boot:             stored on the root filesystem\n'
    fi
    if ((root_size_gib == 0)); then
      printf 'Root:             remaining space, ext4, label %s\n' \
        "${root_label}"
    else
      printf 'Root:             %s GiB, ext4, label %s\n' \
        "${root_size_gib}" "${root_label}"
    fi
    if [[ "${use_home}" == "true" ]]; then
      if ((home_size_gib == 0)); then
        printf 'Home:             remaining space, ext4, label %s\n' \
          "${home_label}"
      else
        printf 'Home:             %s GiB, ext4, label %s\n' \
          "${home_size_gib}" "${home_label}"
      fi
    else
      printf 'Home:             stored on the root filesystem\n'
    fi
    printf 'Swap:             %s GiB, label %s\n' \
      "${swap_size_gib}" "${swap_label}"
    printf 'LVM:              %s\n' "${use_lvm}"
    [[ "${use_lvm}" == "true" ]] \
      && printf 'Volume group:     %s\n' "${volume_group}"
  else
    printf 'Boot:             %s; format: %s\n' \
      "${boot_device:-not separate}" "${format_boot}"
    printf 'Root:             %s; format: %s\n' \
      "${root_device}" "${format_root}"
    printf 'Home:             %s; format: %s\n' \
      "${home_device:-not separate}" "${format_home}"
    printf 'Swap:             %s; recreate: %s\n' \
      "${swap_device:-not configured}" "${format_swap}"
  fi
  printf 'Mount below /mnt: %s\n' "${mount_after_setup}"
}

# Requires explicit confirmation before applying the plan.
confirm_plan() {
  local response=""

  confirm "Does this storage plan look correct?" "no" || {
    die "storage preparation cancelled"
  }
  if [[ "${install_mode}" == "fresh" ]]; then
    printf '\nThis will erase all data on %s.\n' "${target_disk}"
    read -r -p "Type ${target_disk} to continue: " response
    [[ "${response}" == "${target_disk}" ]] || {
      die "disk confirmation did not match"
    }
  fi
}

# Refuses to modify mounted devices or active swap.
ensure_devices_are_idle() {
  local -a devices=("$@")
  local device=""
  local mount_points=""

  for device in "${devices[@]}"; do
    [[ -n "${device}" ]] || continue
    mount_points="$(lsblk --noheadings --output MOUNTPOINTS "${device}")"
    [[ -z "${mount_points//[[:space:]]/}" ]] || {
      die "device is mounted: ${device}"
    }
    swapon --show=NAME --noheadings | grep -Fxq "${device}" && {
      die "device is active swap: ${device}"
    }
  done
}

# Creates a new partition table and storage layout.
partition_fresh_disk() {
  local -a disk_devices=()
  local disk_mib=0
  local start_mib=1
  local root_end_mib=0
  local home_end_mib=0
  local swap_start_mib=0
  local swap_end="100%"
  local lvm_device=""
  local partition_number=1

  mapfile -t disk_devices < <(
    lsblk --raw --paths --noheadings --output NAME "${target_disk}"
  )
  ensure_devices_are_idle "${disk_devices[@]}"
  disk_mib=$(($(blockdev --getsize64 "${target_disk}") / MIB))
  wipefs --all --force "${target_disk}"

  if [[ "${partition_table}" == "gpt" ]]; then
    parted --script "${target_disk}" mklabel gpt
    parted --script "${target_disk}" mkpart ESP fat32 \
      1MiB "$((boot_size_mib + 1))MiB"
    parted --script "${target_disk}" set 1 esp on
    boot_device="$(partition_path "${target_disk}" 1)"
    start_mib=$((boot_size_mib + 1))
    partition_number=2
  else
    parted --script "${target_disk}" mklabel msdos
  fi

  if [[ "${use_lvm}" == "true" ]]; then
    parted --script "${target_disk}" mkpart primary \
      "${start_mib}MiB" 100%
    parted --script "${target_disk}" set "${partition_number}" lvm on
    [[ "${partition_table}" == "mbr" ]] \
      && parted --script "${target_disk}" set 1 boot on
    partprobe "${target_disk}"
    lvm_device="$(partition_path \
      "${target_disk}" "${partition_number}")"
    wait_for_device "${lvm_device}"
    create_lvm_layout "${lvm_device}"
  else
    swap_start_mib=$((disk_mib - swap_size_gib * 1024))
    if ((root_size_gib == 0)); then
      root_end_mib="${swap_start_mib}"
    else
      root_end_mib=$((start_mib + root_size_gib * 1024))
    fi

    parted --script "${target_disk}" mkpart primary ext4 \
      "${start_mib}MiB" "${root_end_mib}MiB"
    root_device="$(partition_path \
      "${target_disk}" "${partition_number}")"
    [[ "${partition_table}" == "mbr" ]] \
      && parted --script "${target_disk}" set 1 boot on
    partition_number=$((partition_number + 1))

    if [[ "${use_home}" == "true" ]]; then
      if ((home_size_gib == 0)); then
        home_end_mib="${swap_start_mib}"
      else
        home_end_mib=$((root_end_mib + home_size_gib * 1024))
        swap_start_mib="${home_end_mib}"
        swap_end="$((swap_start_mib + swap_size_gib * 1024))MiB"
      fi
      parted --script "${target_disk}" mkpart primary ext4 \
        "${root_end_mib}MiB" "${home_end_mib}MiB"
      home_device="$(partition_path \
        "${target_disk}" "${partition_number}")"
      partition_number=$((partition_number + 1))
    elif ((root_size_gib > 0)); then
      swap_start_mib="${root_end_mib}"
      swap_end="$((swap_start_mib + swap_size_gib * 1024))MiB"
    fi
    parted --script "${target_disk}" mkpart primary linux-swap \
      "${swap_start_mib}MiB" "${swap_end}"
    swap_device="$(partition_path \
      "${target_disk}" "${partition_number}")"
    partprobe "${target_disk}"
  fi

  [[ -z "${boot_device}" ]] || wait_for_device "${boot_device}"
  wait_for_device "${root_device}"
  [[ -z "${home_device}" ]] || wait_for_device "${home_device}"
  wait_for_device "${swap_device}"
}

# Creates root, home and swap logical volumes in that order.
create_lvm_layout() {
  local physical_volume="$1"
  local extent_bytes=0
  local free_extents=0
  local swap_extents=0
  local home_extents=0

  pvcreate --force --yes "${physical_volume}"
  vgcreate "${volume_group}" "${physical_volume}"
  if ((root_size_gib > 0)); then
    lvcreate --size "${root_size_gib}G" \
      --name root "${volume_group}"
  fi

  if [[ "${use_home}" == "true" ]] && ((home_size_gib > 0)); then
    lvcreate --size "${home_size_gib}G" \
      --name home "${volume_group}"
  elif [[ "${use_home}" == "true" ]] || ((root_size_gib == 0)); then
    free_extents="$(
      vgs --noheadings --units b --nosuffix \
        --options vg_free_count "${volume_group}" | awk '{print int($1)}'
    )"
    extent_bytes="$(
      vgs --noheadings --units b --nosuffix \
        --options vg_extent_size "${volume_group}" | awk '{print int($1)}'
    )"
    swap_extents=$(((swap_size_gib * GIB + extent_bytes - 1) / \
      extent_bytes))
    home_extents=$((free_extents - swap_extents))
    ((home_extents > 0)) || die "not enough LVM filesystem space"
    if [[ "${use_home}" == "true" ]]; then
      lvcreate --extents "${home_extents}" \
        --name home "${volume_group}"
    else
      lvcreate --extents "${home_extents}" \
        --name root "${volume_group}"
    fi
  fi

  lvcreate --size "${swap_size_gib}G" \
    --name swap "${volume_group}"
  root_device="/dev/${volume_group}/root"
  if [[ "${use_home}" == "true" ]]; then
    home_device="/dev/${volume_group}/home"
  fi
  swap_device="/dev/${volume_group}/swap"
}

# Formats one device with the requested filesystem and label.
format_device() {
  local device="$1"
  local file_system="$2"
  local label="$3"

  case "${file_system}" in
    ext4) mkfs.ext4 -F -L "${label}" "${device}" ;;
    vfat) mkfs.fat -F 32 -n "${label}" "${device}" ;;
    swap) mkswap --force --label "${label}" "${device}" ;;
    *) die "unsupported filesystem: ${file_system}" ;;
  esac
}

# Applies the selected formatting operations.
format_filesystems() {
  if [[ "${format_boot}" == "true" ]]; then
    format_device "${boot_device}" "${boot_file_system}" "${boot_label}"
  fi
  if [[ "${format_root}" == "true" ]]; then
    format_device "${root_device}" ext4 "${root_label}"
  fi
  if [[ "${format_home}" == "true" ]]; then
    format_device "${home_device}" ext4 "${home_label}"
  fi
  if [[ "${format_swap}" == "true" ]]; then
    format_device "${swap_device}" swap "${swap_label}"
  fi
}

# Mounts prepared filesystems below /mnt and enables swap.
mount_filesystems() {
  findmnt --mountpoint /mnt >/dev/null 2>&1 && {
    die "/mnt is already a mount point"
  }

  mkdir -p /mnt
  mount "${root_device}" /mnt
  if [[ -n "${boot_device}" ]]; then
    mkdir -p "/mnt${boot_mount_point}"
    mount "${boot_device}" "/mnt${boot_mount_point}"
  fi
  if [[ -n "${home_device}" ]]; then
    mkdir -p /mnt/home
    mount "${home_device}" /mnt/home
  fi
  [[ -z "${swap_device}" ]] || swapon "${swap_device}"
}

# Prepares selected existing devices for reuse.
prepare_existing_layout() {
  ensure_devices_are_idle \
    "${boot_device}" "${root_device}" "${home_device}" "${swap_device}"
}

# Prints the next manual installation step.
show_completion() {
  log "Storage preparation completed"
  lsblk --paths --output NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS \
    "${target_disk}"
  if [[ "${mount_after_setup}" == "true" ]]; then
    printf '\nThe target is ready below /mnt. Run nixos-install manually.\n'
  else
    printf '\nFilesystems were not mounted. Mount them before installation.\n'
  fi
}

# Coordinates the interactive storage preparation workflow.
main() {
  require_root
  select_target_disk
  select_install_mode
  if [[ "${install_mode}" == "fresh" ]]; then
    configure_fresh_layout
  else
    configure_existing_layout
  fi
  configure_mounting
  show_plan
  confirm_plan
  if [[ "${install_mode}" == "fresh" ]]; then
    partition_fresh_disk
  else
    prepare_existing_layout
  fi
  format_filesystems
  [[ "${mount_after_setup}" == "false" ]] || mount_filesystems
  show_completion
}

main "$@"
