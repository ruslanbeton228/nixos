# NixOS configurations

This repository contains reproducible NixOS configurations.

## Hosts

| Flake output | Directory | Purpose |
| --- | --- | --- |
| `laptop` | `hosts/desktop-laptop` | Laptop with GNOME |
| `workstation` | `hosts/desktop-workstation` | Desktop with GNOME |
| `vps-vpn` | `hosts/vps-vpn` | VPN server |

The desktop hosts use GNOME on Wayland, NetworkManager, PipeWire, Zsh,
Docker and a shared set of applications. User configuration is kept in
the NixOS modules; Home Manager is not used.

## Desktop installation

Run the installation commands from a root shell. Open one before starting:

```console
sudo -i
```

### Preparation scripts

Two independent interactive scripts are provided. The network script is
a standalone bootstrap utility. It does not invoke Nix, download packages
or depend on other repository files. Copy the single file to the installer,
make it executable and run it directly:

```console
cp /path/to/media/setup-network.sh ./setup-network.sh
chmod +x ./setup-network.sh
./setup-network.sh
```

The script asks for an interface, an address such as
`192.168.1.100/24`, a gateway and a DNS resolver. Input fields support
normal Readline editing with arrows, Home, End, Delete and insertion. The
script applies the settings and verifies connectivity and name resolution.

It only expects Bash and standard `coreutils`, `ip` and `ping` commands,
which are available on the NixOS installation image. `resolvectl` and
`getent` are used when present and have built-in fallbacks. Once network
access already works, the flake app remains available as an alternative:

```console
nix run github:ruslanbeton228/nixos#setup-network
```

Prepare storage with:

```console
nix run github:ruslanbeton228/nixos#setup-disk
```

The storage script can create a fresh GPT or MBR layout, with or without
LVM. It can also reuse an existing layout. A separate home filesystem is
preserved by default during reinstallation. No storage is modified until
the complete plan is confirmed.

GPT layouts contain an EFI System Partition. MBR layouts do not create a
separate boot partition: `/boot` remains on the root filesystem. The
filesystem order is boot, root, home and swap where a separate boot
filesystem is required.

The script can mount the prepared filesystems below `/mnt`, but does not
install NixOS. Start the installation separately after reviewing the
layout:

```console
nixos-install \
  --flake github:ruslanbeton228/nixos#workstation
```

Use `laptop` or `vps-vpn` instead when preparing another host. The manual
procedure below documents the desktop GPT and LVM layout.

### Manual installation

The following example creates a GPT disk with an EFI System Partition and
an LVM volume group. LVM contains separate volumes for `/`, `/home` and
swap.

> [!WARNING]
> The partitioning and formatting commands below erase the selected disk.
> Back up important files and verify every device path before continuing.

Boot the current NixOS installer in UEFI mode and open the root shell as
shown above.

### 1. Configure the network manually

First, find the required interface and bring it up. Replace `enp1s0` with
the interface name shown by the first command:

```console
ip -brief link show
ip link set dev enp1s0 up
```

Assign the static address and add the default route. Both commands below
use example values that must be replaced with values for the local
network:

```console
ip -4 address flush dev enp1s0
ip address add 192.168.1.100/24 dev enp1s0
ip route replace default via 192.168.1.1 dev enp1s0
```

Configure DNS through `systemd-resolved`:

```console
resolvectl dns enp1s0 1.1.1.1
resolvectl domain enp1s0 '~.'
```

If `systemd-resolved` is unavailable, write the resolver directly:

```console
printf 'nameserver 1.1.1.1\n' > /etc/resolv.conf
```

Verify the route, external connectivity and DNS resolution:

```console
ip -4 route show
ping -c 3 1.1.1.1
ping -c 3 nixos.org
```

### 2. Identify the target disk

```console
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,MOUNTPOINTS
```

The examples below use an NVMe disk. Change all three paths when using a
different disk. SATA disks normally use paths such as `/dev/sda`,
`/dev/sda1` and `/dev/sda2`.

```console
export TARGET_DISK=/dev/nvme0n1
export EFI_PARTITION=/dev/nvme0n1p1
export LVM_PARTITION=/dev/nvme0n1p2
```

Verify the selected disk once more:

```console
lsblk "$TARGET_DISK"
```

### 3. Create the GPT and LVM partitions

```console
parted "$TARGET_DISK" -- mklabel gpt
parted "$TARGET_DISK" -- mkpart ESP fat32 1MiB 513MiB
parted "$TARGET_DISK" -- set 1 esp on
parted "$TARGET_DISK" -- mkpart primary 513MiB 100%
parted "$TARGET_DISK" -- set 2 lvm on
partprobe "$TARGET_DISK"
```

Create the LVM physical volume, volume group and logical volumes. The
sizes below are examples; adjust the root and swap sizes for the machine.

```console
pvcreate "$LVM_PARTITION"
vgcreate vg0 "$LVM_PARTITION"
lvcreate -L 64G -n root vg0
lvcreate -L 8G -n swap vg0
lvcreate -l 100%FREE -n home vg0
```

### 4. Format and label the filesystems

The labels are part of the host configuration and are case-sensitive:

| Device | Filesystem | Label | Mount point |
| --- | --- | --- | --- |
| EFI partition | FAT32 | `EFI` | `/boot/efi` |
| `vg0/root` | ext4 | `root` | `/` |
| `vg0/home` | ext4 | `home` | `/home` |
| `vg0/swap` | swap | `swap` | swap |

Create the filesystems:

```console
mkfs.fat -F 32 -n EFI "$EFI_PARTITION"
mkfs.ext4 -L root /dev/vg0/root
mkfs.ext4 -L home /dev/vg0/home
mkswap -L swap /dev/vg0/swap
```

Confirm the resulting labels before installing:

```console
lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL
```

### 5. Mount the target system

```console
mount /dev/vg0/root /mnt
mkdir -p /mnt/boot/efi /mnt/home
mount /dev/vg0/home /mnt/home
mount "$EFI_PARTITION" /mnt/boot/efi
swapon /dev/vg0/swap
```

Check the mount layout:

```console
findmnt --target /mnt
findmnt --target /mnt/home
findmnt --target /mnt/boot/efi
swapon --show
```

### 6. Install from GitHub

Choose one flake output:

```console
export TARGET_HOST=workstation
```

Use `laptop` instead when installing the laptop. Install the selected
configuration directly from the owner's GitHub repository:

```console
nixos-install \
  --flake "github:ruslanbeton228/nixos#$TARGET_HOST"
```

Set a password for the desktop user before rebooting:

```console
nixos-enter --root /mnt -c 'passwd roman'
```

Keep a writable clone in the location configured for `nh`:

```console
mkdir -p /mnt/home/roman
git clone https://github.com/ruslanbeton228/nixos \
  /mnt/home/roman/.setup
nixos-enter --root /mnt \
  -c 'chown -R roman:users /home/roman/.setup'
```

Finish the installation:

```console
umount -R /mnt
swapoff /dev/vg0/swap
reboot
```

Remove the installation media when the firmware starts the computer
again.

## Updating a desktop

The `nh` command uses `/home/roman/.setup` automatically on both desktop
hosts.

Pull reviewed changes and activate the new configuration:

```console
cd ~/.setup
git pull --ff-only
nix flake check --no-build
nh os switch
```

To update every flake input locally and switch in one operation:

```console
cd ~/.setup
nh os switch --update
git diff -- flake.lock
```

Review and commit `flake.lock` after a successful update. Dependabot also
opens monthly pull requests for flake inputs and GitHub Actions.

If a new generation has a runtime problem, select an older generation in
the GRUB menu. From a root shell on a running system, switch to the
previous generation with:

```console
nixos-rebuild --rollback switch
```

## Removing old generations

Preview cleanup while keeping at least three generations and everything
created during the last 14 days:

```console
nh clean all --keep 3 --keep-since 14d --dry
```

Run the cleanup after reviewing the preview:

```console
nh clean all --keep 3 --keep-since 14d
```

Cleanup removes old generations and unreachable Nix store paths. Do not
remove a generation that may still be needed for rollback.

## Validation

Before committing configuration changes, run:

```console
find . -type f -name '*.nix' -exec nix fmt -- --check {} +
nix flake check --no-build
```

GitHub Actions runs the flake check for pull requests and pushes to
`main`.
