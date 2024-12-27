#!/bin/bash

set -e

# Initialize variables
P_HOSTNAME=""
P_ZONE_INFO=""
P_LOCALE=""
P_DEVICE=""
P_ROOT_PASSWORD=""
P_USER=""
P_USER_PASSWORD=""
P_ENCRYPT=true
EFI_PARTITION=""
BOOT_PARTITION=""
LVM_PARTITION=""
LVM_UUID=""
SWAP_PARTITION=""
HOME_PARTITION=""
ROOT_PARTITION=""
UEFI=true
[ ! -d /sys/firmware/efi ] && UEFI=false

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

partition_disks() {
	if [[ "$UEFI" == true ]]; then
		gdisk "$P_DEVICE" <<EOF
o
Y
n


+512M
ef00
n


+1G
ef02
n



$( [[ "$P_ENCRYPT" == true ]] && echo 8309 || echo 8300 )
w
y
EOF
	else
		gdisk "$P_DEVICE" <<EOF
o
Y
n


+1G
ef02
n



$( [[ "$P_ENCRYPT" == true ]] && echo 8309 || echo 8300 )
w
y
EOF
	fi

}

split_partitions() {
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
}

format_partitions() {
	# FS formatting
	[[ "$UEFI" == true ]] && mkfs.fat -F32 "$EFI_PARTITION"	# EFI
	mkfs.ext4 "$BOOT_PARTITION"															# BOOT
	mkfs.btrfs -L root "$ROOT_PARTITION"										# ROOT
	mkfs.btrfs -L home "$HOME_PARTITION"										# HOME
	mkswap "$SWAP_PARTITION"																# SWAP
}

mount_partitions() {
	# Partitions mounting
	swapon "$SWAP_PARTITION"								# SWAP
	swapon -a

	mount "$ROOT_PARTITION" /mnt						# ROOT
	mkdir -p /mnt/{home,boot}
	mount "$BOOT_PARTITION" /mnt/boot				# BOOT
	if [[ "$UEFI" == true ]]; then
		mkdir /mnt/boot/efi
		mount "$EFI_PARTITION" /mnt/boot/efi	# EFI
	fi
	mount "$HOME_PARTITION" /mnt/home			# HOME
}

arch_install() {
	pacstrap -K /mnt \
    base \
    base-devel \
    linux \
    linux-firmware \
    lvm2 \
    grub \
    efibootmgr \
		networkmanager

	# Save mounts
	genfstab -U -p /mnt > /mnt/etc/fstab

	# Update keyring
	arch-chroot /mnt /bin/bash -c "
pacman -Sy --noconfirm archlinux-keyring
pacman-key --init
pacman-key --populate archlinux
pacman -Scc --noconfirm
pacman -Sy
"
}

mkinitcpio_configure() {
	local PREV_LINE="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)"
	local NEXT_LINE="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)"
	local NEXT_LINE_ENCRYPT="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)"
	if [[ "$P_ENCRYPT" == true ]]; then
		arch-chroot /mnt /bin/bash -c "sed -i 's/$PREV_LINE/$NEXT_LINE_ENCRYPT/' /etc/mkinitcpio.conf"
	else
		arch-chroot /mnt /bin/bash -c "sed -i 's/$PREV_LINE/$NEXT_LINE/' /etc/mkinitcpio.conf"
	fi

	arch-chroot /mnt /bin/bash -c "mkinitcpio -P"
}

bootloader_install() {
	local command=$([[ "$UEFI" == true ]] && echo "grub-install --efi-directory=/boot/efi" || echo "grub-install --target=i386-pc $P_DEVICE")
	arch-chroot /mnt /bin/bash -c "$command"

	local PREV_LINE='GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet"'
	local NEXT_LINE='GRUB_CMDLINE_LINUX_DEFAULT="loglevel=3 quiet root=/dev/mapper/arch-root cryptdevice=UUID=${LVM_UUID}:arch-lvm"'
	[[ "$P_ENCRYPT" == true ]] && arch-chroot /mnt /bin/bash -c "sed -i 's|$PREV_LINE|$NEXT_LINE|' /etc/default/grub"

	arch-chroot /mnt /bin/bash -c "chmod 600 /boot/initramfs-linux*"
	arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/grub/grub.cfg"
	[[ "$UEFI" == true ]] && arch-chroot /mnt /bin/bash -c "grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg"
}

keyfile_configure() {
	arch-chroot /mnt /bin/bash -c "
mkdir /crypt
dd if=/dev/random of=/crypt/arch_keyfile.bin bs=512 count=8
chmod 000 /crypt/*
cryptsetup luksAddKey $LVM_PARTITION /crypt/arch_keyfile.bin
"
}

# Refresh keyring & Install required dependencies
pacman -Sy --noconfirm archlinux-keyring fzf && clear

handle_options "$@"

partition_disks
EFI_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E '1$' | tail -n 1)
BOOT_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E "$([[ "$UEFI" == true ]] && echo 2 || echo 1)$" | tail -n 1)
LVM_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E "$([[ "$UEFI" == true ]] && echo 3 || echo 2)$" | tail -n 1)
LVM_UUID=$(blkid -s UUID -o value "$LVM_PARTITION")

split_partitions
format_partitions
mount_partitions
arch_install
mkinitcpio_configure
bootloader_install
[[ "$P_ENCRYPT" == true ]] && keyfile_configure
