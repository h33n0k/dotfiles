#!/bin/bash

LOG_LEVELS=("DEBUG" "COMMAND" "EXIT" "INFO" "WARN" "ERROR")
LOG_LEVEL="INFO"
LOG_FILE_NAME="archinstall-journal.log"
LOG_FILE="$LOG_FILE_NAME"
LOG_FILE_EXISTS=true

i=1
while [[ "$LOG_FILE_EXISTS" == true ]]; do
	if [ -f "$LOG_FILE" ]; then
		LOG_FILE=$(echo "$LOG_FILE_NAME" | sed -E "s/archinstall-journal\.log/archinstall-journal-$i.log/g")
	else
		LOG_FILE_EXISTS=false
		touch "$LOG_FILE"
	fi
	((i++))
done

EXIT_STATUS=0
LAST_INFO=""
LAST_COMMAND=""
COMMAND_I=0
WARNINGS=()

update_tui() {
	tput sc      # Save cursor position
	tput cup 0 0 # Move cursor to the top-left corner

	clear_line() {
		tput cr
		tput el
	}

	# Get width of stdout
	width=$(echo "$log_output" | awk '{print length($0)}' | sort -n | tail -n 1)
	box_width=$((width + 4)) # Add 4 for padding

	break_line() {
		clear_line
		printf "%-${box_width}s\n" | tr ' ' '-'
	}

	clear_line
	[[ ! -z "$LAST_INFO" ]] && printf "%-8s %-15s\n" "STATUS:" "$LAST_INFO"
	clear_line
	[[ ! -z "$LAST_COMMAND" ]] && printf "%-8s %-15s\n" "COMMAND:" "$LAST_COMMAND"

	break_line

	if [ ${#WARNINGS[@]} -ne 0 ]; then
		IFS=$'\n'
		for w in ${WARNINGS[@]}; do
			clear_line
			printf "%-8s %-15s\n" "WARNING:" "$w"
		done
		break_line
	fi

	# Get the last 15 lines from log file
	log_output=$(tail -n 15 "$LOG_FILE")
	while IFS= read -r line; do
		clear_line
		printf "%-${width}s\n" "$line"
	done <<<"$log_output"

	[[ -z "$1" ]] && tput rc # Restore cursor position
}

journal_log() {
	local message=""
	local LEVEL="$LOG_LEVEL"

	OPTIND=1

	while getopts "m:l:" opt; do
		case $opt in
		m) message="$OPTARG" ;;
		l) LEVEL="$OPTARG" ;;
		esac
	done

	local timestamp=$(date +"%Y-%m-%d %H:%M:%S")
	if [[ ! -z "$message" ]]; then
		case "$LEVEL" in
		INFO) LAST_INFO="$message" ;;
		COMMAND) [[ -z "$(echo "$message" | grep 'END')" ]] && LAST_COMMAND="$message" ;;
		WARNING) WARNINGS+=("$message") ;;
		esac
		echo "[$timestamp] [$LEVEL] $message" >>"$LOG_FILE"
	fi
	update_tui
}

exit_script() {
	tput sgr0
	if [ $EXIT_STATUS -ne 0 ]; then
		journal_log -l "INFO" -m "An error occured."
	else
		journal_log -l "INFO" -m "Sucessfully exiting."
	fi
	update_tui false
	echo
}

trap exit_script EXIT

journal_throw() {
	local status=$([[ -z "$2" ]] && echo 1 || echo "$2")
	journal_log -l "ERROR" -m "$1"
	EXIT_STATUS="$status"
	exit $status
}

# Usage: journal_command <command> <chroot? (default: false)> <exit_on_fail? (default: true)>
journal_command() {
	journal_log -l "COMMAND" -m "(#$COMMAND_I) $1"

	TMP_OUTPUT=$(mktemp)

	if [[ "$2" == true ]]; then
		arch-chroot /mnt /bin/bash -c "$1" >>"$TMP_OUTPUT" 2>&1
	else
		eval "$1" >>"$TMP_OUTPUT" 2>&1
	fi

	EXIT_STATUS="$?"

	while IFS= read -r line; do
		echo "$line" >>"$LOG_FILE"
		update_tui
	done <"$TMP_OUTPUT"

	journal_log -l "EXIT" -m "(#$COMMAND_I) $EXIT_STATUS"

	if [ $EXIT_STATUS -ne 0 ]; then
		if [ -z "$3" ] || [[ "$3" == true ]]; then
			journal_throw "command #$COMMAND_I exited with status $EXIT_STATUS" "$EXIT_STATUS"
		else
			journal_log -l "WARNING" -m "'$1' exited with $EXIT_STATUS"
			EXIT_STATUS=0
		fi
	fi

	((COMMAND_I++))
	rm -r "$TMP_OUTPUT"
	echo
}

check_block() {
	[[ ! -b "$1" ]] && journal_throw "$1 is not a valid block."
}

# Initialize variables
P_HOSTNAME=""
P_ZONE_INFO=""
P_LOCALE=""
P_DEVICE=""
P_PASSPHRASE=""
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

	[[ -z "$P_DEVICE" ]] && echo "device: " && P_DEVICE=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/" $1 " (" $2 ")"}' | fzf --prompt="Select a device: " --height 40% --border | awk '{print $1}')
	[[ -z "$P_HOSTNAME" ]] && prompt "P_HOSTNAME" "hostname: "
	[[ "$P_ENCRYPT" == true ]] && [[ -z "$P_PASSPHRASE" ]] && prompt "P_PASSPHRASE" "encryption passphrase: "
	[[ -z "$P_ROOT_PASSWORD" ]] && prompt "P_ROOT_PASSWORD" "root password: "
	[[ -z "$P_USER" ]] && prompt "P_USER" "new user: "
	[[ -z "$P_USER_PASSWORD" ]] && prompt "P_USER_PASSWORD" "password: "
	[[ -z "$P_ZONE_INFO" ]] && echo "zone info: " && P_ZONE_INFO=$(find /usr/share/zoneinfo/ -type f | fzf --preview 'echo {} | cut -d/ -f5- | tr "/" " "' --height 40% --border --preview-window=down:1:wrap)
	[[ -z "$P_LOCALE" ]] && echo "locale: " && P_LOCALE=$(grep -E '^.*UTF-8' /etc/locale.gen | fzf --preview 'echo {}' --height 40% --border --preview-window=down:3:wrap)

	local EMPTY_CHECKS=(
		"P_DEVICE"
		"P_ROOT_PASSWORD"
		"P_USER"
		"P_USER_PASSWORD"
		"P_ZONE_INFO"
		"P_LOCALE"
	)

	for check in ${EMPTY_CHECKS[@]}; do
		value=$(eval "echo \$$check")
		[[ -z "$value" ]] && journal_throw "${check#P_} must not be empty."
	done

	[[ "$P_ENCRYPT" == true ]] && [[ -z "$P_PASSPHRASE" ]] && journal_throw "PASSPHRASE must not be empty."
	check_block "$P_DEVICE"
}

partition_disks() {
	journal_log -m "Disk partitioning"
	local LVM_TYPE="$([[ "$P_ENCRYPT" == true ]] && echo 8309 || echo 8300)"
	journal_command "sgdisk --zap-all $P_DEVICE"                                                  # Clear the partition table
	[[ "$UEFI" == true ]] && journal_command "sgdisk --new=0:0:+512M --typecode=0:ef00 $P_DEVICE" # Create first partition with 512MB and type ef00
	journal_command "sgdisk --new=0:0:+1G --typecode=0:ef02 $P_DEVICE"                            # Create second partition with 1GB and type ef02
	journal_command "sgdisk --new=0:0:0 --typecode=0:$LVM_TYPE $P_DEVICE"                         # Create third partition with remaining space
	journal_command "sgdisk --print $P_DEVICE"                                                    # Print the partition table

	EFI_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E '1$' | tail -n 1)
	BOOT_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E "$([[ "$UEFI" == true ]] && echo 2 || echo 1)$" | tail -n 1)
	LVM_PARTITION=$(lsblk -lnpo NAME "$P_DEVICE" | grep -E "$([[ "$UEFI" == true ]] && echo 3 || echo 2)$" | tail -n 1)

	check_block "$EFI_PARTITION"
	check_block "$BOOT_PARTITION"
  [[ "$UEFI" == true ]] && check_block "$EFI_PARTITION"
}

split_partitions() {
	journal_log -m "Splitting partitions"
	sleep 5s

	if [[ "$P_ENCRYPT" == true ]]; then
		# Load encryption modules
		journal_command "modprobe dm-crypt"
		journal_command "modprobe dm-mod"

		# Encrypt partition
		journal_command "echo -n '$P_PASSPHRASE' | cryptsetup luksFormat -q --cipher aes-xts-plain64 --key-size 512 --hash sha512 '$LVM_PARTITION'" # Encrypt
		journal_command "echo -n '$P_PASSPHRASE' | cryptsetup open '$LVM_PARTITION' arch-lvm"                                                       # Open

		# LVM partitioning
		journal_command "pvcreate -ff -y /dev/mapper/arch-lvm"  # Create physical volume
		journal_command "vgcreate -y arch /dev/mapper/arch-lvm" # Create volume group

		HOME_PARTITION="/dev/mapper/arch-home"
		ROOT_PARTITION="/dev/mapper/arch-root"
		SWAP_PARTITION="/dev/mapper/arch-swap"
	else
		journal_command "pvcreate -ff -y $LVM_PARTITION"  # Create physical volume
		journal_command "vgcreate -y arch $LVM_PARTITION" # Create volume group

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

	# Create logical volumes (auto-confirm overwrite with `-y`)
	lvcreate -n swap -L "$SWAP_PARTITION_SIZE" -C y arch # SWAP
	lvcreate -n root -L "$ROOT_PARTITION_SIZE" -C y arch # ROOT
	lvcreate -n home -l +100%FREE arch                   # HOME
}

format_partitions() {
	journal_log -m "Formating partitions"
	[[ "$UEFI" == true ]] && mkfs.fat -F32 "$EFI_PARTITION" # EFI
	journal_command "mkfs.ext4 -F $BOOT_PARTITION"          # BOOT
	journal_command "mkfs.btrfs -f -L root $ROOT_PARTITION" # ROOT
	journal_command "mkfs.btrfs -f -L home $HOME_PARTITION" # HOME
	journal_command "mkswap -f $SWAP_PARTITION"             # SWAP

	LVM_UUID=$(blkid -s UUID -o value "$LVM_PARTITION" 2>/dev/null)
	[[ -z "$LVM_UUID" ]] && journal_throw "LVM uuid must be defined"
}

mount_partitions() {
	journal_log -m "Mounting partitions"
	journal_command "swapon $SWAP_PARTITION" # SWAP
	journal_command "swapon -a"

	journal_command "mount $ROOT_PARTITION /mnt" # ROOT
	journal_command "mkdir -p /mnt/{home,boot}"
	journal_command "mount $BOOT_PARTITION /mnt/boot" # BOOT
	if [[ "$UEFI" == true ]]; then
		journal_command "mkdir /mnt/boot/efi"
		journal_command "mount $EFI_PARTITION /mnt/boot/efi" # EFI
	fi
	journal_command "mount "$HOME_PARTITION" /mnt/home" # HOME
}

arch_install() {
	journal_log -m "Installing archlinux"
	local PACKAGES=(
		"base"
		"base-devel"
		"linux"
		"linux-firmware"
		"lvm2"
		"grub"
		"efibootmgr"
		"networkmanager"
	)

	local COMMANDS=(
		"pacman -Sy --noconfirm archlinux-keyring"
		"pacman-key --init"
		"pacman-key --populate archlinux"
		"pacman -Scc --noconfirm"
		"pacman -Sy"
		"pacman -Scc --noconfirm"
	)

	IFS=' '
	journal_command "pacstrap -K /mnt ${PACKAGES[*]}" false false

	# Save mounts
	journal_command "genfstab -U -p /mnt >/mnt/etc/fstab"

	journal_log -m "Updating keyring and sources"
	IFS=$'\n'
	for command in ${COMMANDS[@]}; do
		journal_command "$command" true
	done
}

mkinitcpio_configure() {
	journal_log -m "Configuring initcpio"

	local PREV_LINE="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck)"
	local NEXT_LINE="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block lvm2 filesystems fsck)"
	local NEXT_LINE_ENCRYPT="HOOKS=(base udev autodetect microcode modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems fsck)"
	journal_command "sed -i 's/$PREV_LINE/$([[ "$P_ENCRYPT" == true ]] && echo "$NEXT_LINE_ENCRYPT" || echo "$NEXT_LINE")/' /etc/mkinitcpio.conf" true
	journal_command "mkinitcpio -P" true false
}

bootloader_install() {
	local command=$([[ "$UEFI" == true ]] && echo "grub-install --efi-directory=/boot/efi" || echo "grub-install --target=i386-pc $P_DEVICE")
	journal_command "arch-chroot /mnt /bin/bash -c '$command'"

	local LINE="GRUB_CMDLINE_LINUX_DEFAULT"
	local CMDLINE_DEFAULT="loglevel=3 quiet root=/dev/mapper/arch-root"
	[[ "$P_ENCRYPT" == true ]] && CMDLINE_DEFAULT="$CMDLINE_DEFAULT cryptdevice=UUID=$LVM_UUID:arch-lvm"
	local NEXT_LINE="$LINE=\\\"$CMDLINE_DEFAULT\\\""
	journal_command "sed -i 's|^$LINE.*|$NEXT_LINE|' /etc/default/grub" true

	journal_command "chmod 600 /boot/initramfs-linux*" true
	journal_command "grub-mkconfig -o /boot/grub/grub.cfg" true
	[[ "$UEFI" == true ]] && journal_command "grub-mkconfig -o /boot/efi/EFI/arch/grub.cfg" true
}

keyfile_configure() {
	local KEYFILE="arch_keyfile.bin"
	journal_command "mkdir /crypt" true false
	journal_command "dd if=/dev/random of=/crypt/$KEYFILE bs=512 count=8 && chmod 000 /crypt/*" true
	journal_command "echo -n '$P_PASSPHRASE' | cryptsetup luksAddKey $LVM_PARTITION /crypt/$KEYFILE" true
}

set_users() {
	journal_command "echo $P_HOSTNAME > /etc/hostname" true
	journal_command "echo 'root:$P_ROOT_PASSWORD' | chpasswd" true
	journal_command "useradd -m -G wheel -s /bin/bash $P_USER" true
	journal_command "echo '$P_USER:$P_USER_PASSWORD' | chpasswd" true
	journal_command "sed -i 's|^# %wheel ALL=(ALL:ALL) ALL|%wheel ALL=(ALL:ALL) ALL|' /etc/sudoers" true
}

set_lang() {
	local NEXT_LINE="${P_LOCALE#\#}"
	LOCALE="LANG=$(echo $NEXT_LINE | sed 's/ UTF-8$//')"
	journal_command "ln -sf $P_ZONE_INFO /etc/localtime" true
	journal_command "sed -i 's|$P_LOCALE|$NEXT_LINE|' /etc/locale.gen" true
	journal_command "locale-gen" true
	journal_command "echo $LOCALE > /etc/locale.conf" true
}

set_clock() {
	NTP=(
		"0.arch.pool.ntp.org"
		"1.arch.pool.ntp.org"
		"2.arch.pool.ntp.org"
		"3.arch.pool.ntp.org"
	)

	FALLBACK=(
		"0.pool.ntp.org"
		"1.pool.ntp.org"
	)

	IFS=' '
	CONF_FILE="/etc/systemd/timesyncd.conf"
	journal_command "echo 'NTP=${NTP[*]}' >> $CONF_FILE" true
	journal_command "echo 'FallbackNTP=${FALLBACK[*]}' >> $CONF_FILE" true
	journal_command "systemctl enable systemd-timesyncd.service" true
}

# Refresh keyring & Install required dependencies
pacman -Sy --noconfirm archlinux-keyring fzf && clear

clear
handle_options "$@"

journal_log -l "INFO" -m "Starting"
partition_disks
split_partitions
format_partitions
mount_partitions
arch_install
mkinitcpio_configure
bootloader_install
[[ "$P_ENCRYPT" == true ]] && keyfile_configure
set_users
set_lang
set_clock
