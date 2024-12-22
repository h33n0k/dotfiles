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

case "$DIST" in
	arch) sudo pacman -S --noconfirm base-devel ;;
esac

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

# Read modules
modules="[]"
managers=("pacman" "aur" "apt")
for element in $BASE_DIR/*; do
	[[ ! -d $element ]] && continue
	config="$element/.module.toml"
	[[ ! -f "$config" ]] && continue
	packages="{}"
	for manager in ${managers[@]}; do
		list="[]"
		if tomlq -r ".dependencies.$manager[]" "$config" > /dev/null 2>&1; then
			for package in $(tomlq -r ".dependencies.$manager[]" "$config"); do
				list=$(echo "$list" | jq -c --arg package "$package" '. + [$package]')
			done
		fi
		packages=$(echo "$packages" | jq --arg manager "$manager" --argjson packages "$list" '. + {($manager): $packages}')
	done

	scripts="[]"
	if tomlq -r '.scripts[]' $config > /dev/null 2>&1; then
		IFS=$'\n'
		for script in $(tomlq -rc '.scripts[] | { path: .path, description: .description }' "$config"); do
			file="$(echo "$script" | jq -rc '.path')"
			description="$(echo "$script" | jq -rc '.description')"
			[[ "$file" != /* ]] && path="$(realpath "$element/$file")" || path="$file"
			scripts=$(echo "$scripts" | jq -c \
				--arg path "$path" \
				--arg description "$description" \
				'. + [{ path: $path, description: $description }]'
			)
		done
	fi

	dependencies=$(jq -n \
		--argjson packages "$packages" \
		--argjson scripts "$scripts" \
		'{ packages: $packages, scripts: $scripts }'
	)

	modules=$(jq -c \
		--argjson module "$(jq -n \
			--arg path "$element" \
			--arg type "$(tomlq -r '.module.type' $config)" \
			--arg name "$(tomlq -r '.module.name' $config)" \
			--arg description "$(tomlq -r '.module.description' $config)" \
			--argjson dependencies "$dependencies" \
			'{ path: $path, selected: true, name: $name, description: $description, type: $type, dependencies: $dependencies }'
			)" \
		'. + [$module]' \
		<<< "$modules"
	)
done

hide_cursor() {
	echo -ne "\e[?25l" > /dev/tty
}

show_cursor() {
	echo -ne "\e[?25h" > /dev/tty
}

# Ensure cursor visibility when exiting
trap 'show_cursor' EXIT

ascii() {
	echo -e "
██╗  ██╗██████╗ ██████╗ ███╗   ██╗ ██████╗ ██╗  ██╗
██║  ██║╚════██╗╚════██╗████╗  ██║██╔═████╗██║ ██╔╝
███████║ █████╔╝ █████╔╝██╔██╗ ██║██║██╔██║█████╔╝
██╔══██║ ╚═══██╗ ╚═══██╗██║╚██╗██║████╔╝██║██╔═██╗
██║  ██║██████╔╝██████╔╝██║ ╚████║╚██████╔╝██║  ██╗
╚═╝  ╚═╝╚═════╝ ╚═════╝ ╚═╝  ╚═══╝ ╚═════╝ ╚═╝  ╚═╝
	" | sed "s/\(.*\)/\x1b[35m\1\x1b[0m/"
}

display_item() {
	echo "$4$(parse_echo $([[ $3 == false ]] && echo "#cad3f5" || echo "#8bd5ca"))[$( [[ $2 == true ]] && echo "X" || echo " " )] $1 $(parse_echo "#6e738d")$5"
}

get_motion() {
	local key
	read -s -N1 key
	case "$key" in
		$'\n') echo "enter" ;;
		' ') echo "space" ;;
		A|k) echo "up" ;;
		B|j) echo "down" ;;
		B|q) echo "quit" ;;
	esac
}

prompt_menu() {
	local items="[]"
	while getopts "p:i:" opt; do
		case $opt in
			p) prompt=$OPTARG ;;
			i) items=$(echo "$OPTARG" | jq -c 'group_by(.type) | map({type: .[0].type, selected: false, items: .})') ;;
		esac
	done

	# Assign index to elements
	local i=0
	local ti=0
	for type in $(echo "$items" | jq -c '.[]'); do
		items=$(echo "$items" | jq -c --arg ti "$ti" --arg value "$i" '.[$ti|tonumber] += { index: $value }')
		(( i++ ))
		local mi=0
		for item in $(echo "$type" | jq -c '.items[]'); do
			items=$(echo "$items" | jq -c --arg ti "$ti" --arg mi "$mi" --arg value "$i" '.[$ti|tonumber].items[$mi|tonumber] += { index: $value }')
			(( i++ ))
			(( mi++ ))
		done
		(( ti++ ))
	done

	local current=0
	local update=true
	local selected=false
	hide_cursor
	while [ $selected = false ]; do
		if [[ $update = true ]]; then
			clear > /dev/tty
			ascii > /dev/tty
			echo -e "$(parse_echo "#c6a0f6")$prompt:" > /dev/tty
			echo > /dev/tty
			for type in $(echo "$items" | jq -c '.[]'); do
				display_item \
					$(jq -r '.type' <<< "$type") \
					$(jq -r '.selected' <<< "$type") \
					$([[ $current == $(jq -r '.index' <<< "$type") ]] && echo true || echo false) \
					> /dev/tty
									for item in $(echo "$type" | jq -c '.items[]'); do
										display_item \
											$(jq -r '.name' <<< "$item") \
											$(jq -r '.selected' <<< "$item") \
											$([[ $current == $(jq -r '.index' <<< "$item") ]] && echo true || echo false) \
											"  " \
											$(jq -r '.description' <<< "$item") > /dev/tty
										done
									done

									echo > /dev/tty
									echo -e "$(parse_echo "#f5bde6")Press enter to continue.$(reset_echo)" > /dev/tty

									update=false
		fi

		local motion=$(get_motion)
		case $motion in
			up)
				(( current = (current - 1 + i) % i ))
				update=true
				;;
			down)
				(( current = (current + 1) % i ))
				update=true
				;;
			space)
				update=true
				type=$(jq --arg i "$current" '.[] | select(.index == $i)' <<< "$items")
				if [[ -z "$type" || "$type" == "null" ]]; then
					echo "$current" > /dev/tty
					items=$(jq -c \
						--arg index "$current" \
						'map(.items |= map(if .index == $index then .selected = if .selected == true then false else true end else . end))' \
						<<< "$items"
					)
				else
					items=$(jq -c \
						--arg type "$(jq -r '.type' <<< "$type")" \
						--arg selected "$([[ $(jq -r '.selected' <<< "$type") == true ]] && echo false || echo true)" \
						'map(if .type == $type then .selected = ($selected|fromjson) | .items |= map(.selected = ($selected|fromjson)) else . end)' \
						<<< "$items"
					)
				fi
				;;
			enter) selected=true ;;
			quit) exit 1 ;;
		esac
	done

	jq -c '[.[] | .items[] | select(.selected == true)]' <<< "$items"
}

selected=$(prompt_menu -p "Select modules to enable" -i "$modules")

# list packages dependencies
packages="{}"
for manager in ${managers[@]}; do
	array="[]"
	for item in $(jq -c '.[]' <<< "$selected"); do
		for package in $(jq -cr ".dependencies.packages.$manager[]" <<< "$item"); do
			array=$(jq -c --arg package "$package" '. + [$package]' <<< "$array")
		done
	done
	packages=$(jq -c --arg name "$manager" --argjson array "$array" '. + { $name: $array }' <<< "$packages")
done

scripts="[]"
for item in $(jq -c '.[]' <<< "$selected"); do
	for script in $(jq -c '.dependencies.scripts[]' <<< "$item"); do
		scripts=$(jq --arg path "$(jq -r '.path' <<< "$script")" '. + [$path]' <<< "$scripts")
	done
done

# Install dependencies
case "$DIST" in
	arch)
		# Install pacman packages
		sudo pacman -Sy $(jq -r '[.pacman[]] | unique | .[]' <<< "$packages")

		# Install aur packages
		for repo in $(jq -r '[.aur[]] | unique | .[]' <<< "$packages"); do
			dir="/tmp/aur_$dir$(echo "$repo" | sed 's|.*/||; s|\.git$||')"
			git clone "$repo" "$dir"
			if [[ -d "$dir" ]]; then
				cd "$dir" || exit 1
				makepkg -sic --noconfirm
				cd - || exit 1
				rm -rf "$dir"
			fi
		done
		;;

	debian) sudo apt-get install $(jq -r '[.apt[]] | unique | .[]' <<< "$packages") ;;
esac

# Run scripts
for script in $(jq -cr '.[]' <<< "$scripts"); do
	if [ ! -f "$script" ]; then
		echo "$(parse_echo "$COLOR_RED")Could not locate $script.$(reset_echo)"
		continue
	fi
	chmod +x "$script"
	$script
done
