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

	[[ -z "$P_HOSTNAME" ]] && prompt "P_HOSTNAME" "hostname: "
	[[ -z "$P_ROOT_PASSWORD" ]] && prompt "P_ROOT_PASSWORD" "root password: "
	[[ -z "$P_USER" ]] && prompt "P_USER" "new user: "
	[[ -z "$P_USER_PASSWORD" ]] && prompt "P_USER_PASSWORD" "password: "
	[[ -z "$P_ZONE_INFO" ]] && echo "zone info: " && P_ZONE_INFO=$(find /usr/share/zoneinfo/ -type f | fzf --preview 'echo {} | cut -d/ -f5- | tr "/" " "' --height 40% --border --preview-window=down:1:wrap)
	[[ -z "$P_DEVICE" ]] && echo "device: " && P_DEVICE=$(lsblk -o NAME,SIZE,TYPE | grep disk | awk '{print "/dev/" $1 " (" $2 ")"}' | fzf --prompt="Select a device: " --height 40% --border | awk '{print $1}')
	[[ -z "$P_LOCALE" ]] && echo "locale: " && P_LOCALE=$(grep -E '^.*UTF-8' /etc/locale.gen | awk '{print $1}' | fzf --preview 'echo {}' --height 40% --border --preview-window=down:3:wrap)
}

# Call the function to handle options
handle_options "$@"

echo "hostname: $P_HOSTNAME"
echo "zone_info: $P_ZONE_INFO"
echo "locale: $P_LOCALE"
echo "device: $P_DEVICE"
echo "root_password: $P_ROOT_PASSWORD"
echo "user: $P_USER"
echo "user_password: $P_USER_PASSWORD"
echo "encrypt: $P_ENCRYPT"
