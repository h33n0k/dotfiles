#!/bin/bash

set -e

# Refresh keyring
pacman -Sy --noconfirm archlinux-keyring fzf && clear

# Initialize variables
P_HOSTNAME=""
P_ZONE_INFO=""
P_LOCALE=""
P_DEVICE=""
P_ROOT_PASSWORD=""
P_USER=""
P_USER_PASSWORD=""
P_ENCRYPT=true

# Function to handle parameters
handle_options() {
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--no-encrypt)
				P_ENCRYPT=false
				shift
				;;
			--hostname)
				P_HOSTNAME="$2"
				shift 2
				;;
			--zone-info)
				P_ZONE_INFO="$2"
				shift 2
				;;
			--locale)
				P_LOCALE="$2"
				shift 2
				;;
			--device)
				P_DEVICE="$2"
				shift 2
				;;
			--root-password)
				P_ROOT_PASSWORD="$2"
				shift 2
				;;
			--user)
				P_USER="$2"
				shift 2
				;;
			--user-password)
				P_USER_PASSWORD="$2"
				shift 2
				;;
			*)
				echo "Unknown option: $1"
				exit 1
				;;
		esac
	done

	prompt() {
		local var="$1"
		local prompt="$2"
		read -p "$prompt" value
		eval "$var='$value'"
	}

	# [[ -z "$P_HOSTNAME" ]] && prompt "P_HOSTNAME" "hostname: "
	# [[ -z "$P_ROOT_PASSWORD" ]] && prompt "P_ROOT_PASSWORD" "root password: "
	# [[ -z "$P_USER" ]] && prompt "P_USER" "new user: "
	# [[ -z "$P_USER_PASSWORD" ]] && prompt "P_USER_PASSWORD" "password: "
	# [[ -z "$P_ZONE_INFO" ]] && echo "zone info: " && P_ZONE_INFO=$(find /usr/share/zoneinfo/ -type f | fzf --preview 'echo {} | cut -d/ -f5- | tr "/" " "' --height 40% --border --preview-window=down:1:wrap)
	[[ -z "$P_DEVICE" ]] && echo "device: " && P_DEVICE=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/" $1 " (" $2 ")"}' | fzf --prompt="Select a device: " --height 40% --border | awk '{print $1}')
	# [[ -z "$P_LOCALE" ]] && echo "locale: " && P_LOCALE=$(grep -E '^.*UTF-8' /etc/locale.gen | awk '{print $1}' | fzf --preview 'echo {}' --height 40% --border --preview-window=down:3:wrap)
}

handle_options "$@"

# Partitioning disks
gdisk "$P_DEVICE" <<EOF
o
Y
n
1

+512M
ef00
n
2

+1G
ef02
n
3


$( [[ "$P_ENCRYPT" == true ]] && echo 8309 || echo 8300 )
w
y
EOF

# Define partitions
EFI_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E '1$' | tail -n 1)
BOOT_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E '2$' | tail -n 1)
LVM_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E '3$' | tail -n 1)
SWAP_PARTITION=""
HOME_PARTITION=""
ROOT_PARTITION=""

if [[ "$P_ENCRYPT" == true ]]; then
	# Load encryption modules
	modprobe dm-crypt
	modprobe dm-mod

	# Encrypt partition
	cryptsetup luksFormat -v -s 512 -h sha512 "$LVM_PARTITION"	# Encrypt
	cryptsetup open "$LVM_PARTITION" arch-lvm										# Open

	# LVM partitioning
	pvcreate /dev/mapper/arch-lvm       # Create physical volume
	vgcreate arch /dev/mapper/arch-lvm  # Create volume group

	HOME_PARTITION="/dev/mapper/arch-home"
	ROOT_PARTITION="/dev/mapper/arch-root"
	SWAP_PARTITION="/dev/mapper/arch-swap"
else
	pvcreate "$LVM_PARTITION"				# Create physical volume
	vgcreate arch "$LVM_PARTITION"	# Create volume group

	HOME_PARTITION="/dev/arch/home"
	ROOT_PARTITION="/dev/arch/root"
	SWAP_PARTITION="/dev/arch/swap"
fi

TOTAL_SIZE=$(lsblk -o SIZE -n "$LVM_PARTITION" | head -n 1 | tr -d '[:space:]G')

compute_size() {
	fr=$(printf "%.2f\n" $(echo "$TOTAL_SIZE / 10" | bc -l))
	printf "%.2fG\n" $(echo "$fr * $1" | bc -l)
}

SWAP_PARTITION_SIZE="$(compute_size 1)"
ROOT_PARTITION_SIZE="$(compute_size 4)"

# Create logical volumes
lvcreate -n swap -L "$SWAP_PARTITION_SIZE" -C y arch  # SWAP
lvcreate -n root -L "$ROOT_PARTITION_SIZE" -C y arch  # ROOT
lvcreate -n home -l +100%FREE arch										# HOME

# FS formatting
mkfs.fat -F32 "$EFI_PARTITION"				# EFI
mkfs.ext4 "$BOOT_PARTITION"						# BOOT
mkfs.btrfs -L root "$ROOT_PARTITION"	# ROOT
mkfs.btrfs -L home "$HOME_PARTITION"	# HOME
mkswap "$SWAP_PARTITION"							# SWAP

# Partitions mounting
## SWAP
swapon "$SWAP_PARTITION"
swapon -a

mount "$ROOT_PARTITION" /mnt					# ROOT
mkdir -p /mnt/{home,boot}
mount "$BOOT_PARTITION" /mnt/boot			# BOOT
mkdir /mnt/boot/efi
mount "$EFI_PARTITION" /mnt/boot/efi	# EFI
mount "$HOME_PARTITION" /mnt/home			# HOME