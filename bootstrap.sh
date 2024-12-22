#!/bin/bash

COLOR_RED="#ed8796"
COLOR_MAROON="#ee99a0"
COLOR_PEACH="#f5a97f"

BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)" # Get current pwd
DIST="$(. /etc/os-release && echo "$ID")" # Get current linux distribution

# Initialize variables
UPDATE_REQUIRED=false

# Parse the options
while [[ $# -gt 0 ]]; do
	case $1 in
		--update-required)
			UPDATE_REQUIRED=true
			shift
			;;
	esac
done

# Update sources
case "$DIST" in
	arch) sudo pacman -Syy ;;
	debian) sudo apt-get update ;;
esac

# Install required tools
for package in jq git yq; do
	if ! command -v "$package" > /dev/null 2>&1; then
		case "$DIST" in
			arch) sudo pacman -S --noconfirm "$package" ;;
			debian) sudo apt-get install -y "$package" ;;
		esac
	fi

done

parse_echo() {
	# Convert hex color code to RGB and return an ANSI escape code for color
	echo -e "\033[38;2;$(printf "%d;%d;%d" 0x${1:1:2} 0x${1:3:2} 0x${1:5:2})m"
}

reset_echo() {
	# Reset color formatting to default
	echo -e "\033[0m"
}

compare_version() {
	# Compare two versions, return 0 if $1 >= $2, else return 1
	if ! [[ "$(printf '%s\n' "$1" "$2" | sort -V | head -n1)" == "$1" ]] > /dev/null 2>&1; then
		[[ $UPDATE_REQUIRED == true ]] && return 1 # auto install
		echo "$(parse_echo "$COLOR_RED")'$3' does not match the required version >= $1." > /dev/tty
		echo "$(parse_echo "$COLOR_MAROON")Installed: $2" > /dev/tty
		echo "$(parse_echo "$COLOR_PEACH")Install required version ? (Y/N)$(reset_echo)" > /dev/tty

		# Check the user's input
		read -n 1 choice
		[[ -z "$choice" ]] && choice="Y"
		case "$choice" in
			[Yy]* )
				echo "$(reset_echo)"
				return 1
				;;
			* ) exit 1 > /dev/tty ;;
		esac
	fi

	return 0
}

# Check jq version
if ! compare_version "1.7.1" "$(jq --version 2>/dev/null | sed 's/^jq-//')" "jq" > /dev/null 2>&1; then
	curl -Lo $BASE_DIR/jq https://github.com/jqlang/jq/releases/download/jq-1.7.1/jq-linux64
	chmod +x $BASE_DIR/jq
	sudo mv $BASE_DIR/jq /usr/bin/jq
fi

jq --version
