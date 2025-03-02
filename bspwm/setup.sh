#!/bin/bash

# Disable `unset` flag
set +u

BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)" # Get current pwd
BSPWM_CONFIG_FILE="$BASE_DIR/.config/bspwm/bspwmrc"
SXHKD_CONFIG_FILE="$BASE_DIR/.config/sxhkd/sxhkdrc"

if [ -f "$SXHKD_CONFIG_FILE" ]; then
	chmod +x "$SXHKD_CONFIG_FILE"
else
	echo "Could not find bspwm configuration file."
	echo "$SXHKD_CONFIG_FILE"
	exit 1
fi

if [ ! -f "$BSPWM_CONFIG_FILE" ]; then
	echo "Could not find bspwm configuration file."
	echo "$BSPWM_CONFIG_FILE"
	exit 1
fi

chmod +x "$BSPWM_CONFIG_FILE"

define_monitor() {
	local monitor="${1:-}"
	local NAME="$monitor "
	[[ "$monitor" -eq "" ]] && NAME=""
	local START="${2:-1}"
	local END="${3:-$(echo "$START + 1" | bc)}"
	local LINE="bspc monitor $NAME-d"
	local i="$START"
	while [[ "$i" -lt "$END" ]]; do
		LINE+=" $i"
		((i++))
	done
	sed -i "2a $LINE" "$BSPWM_CONFIG_FILE"
}

validate_input() {
	local INPUT="$1"
	if [[ "$INPUT" =~ ^[0-9]+(\ [0-9]+)*$ ]]; then
		echo 0
	else
		echo 1
	fi
}

if command -v xrandr > /dev/null 2>&1; then
	MONITORS=$(xrandr -q | grep " connected" | awk '{print $1}')


	if [[ $(echo "$MONITORS" | wc -l) == 1 ]]; then
		define_monitor "$MONITORS" 1 4
	else

		list=()
		order=()

		i=1
		for monitor in $MONITORS; do
			echo "$i. $monitor"
			list+=("$monitor")
			((i++))
		done

		# Order prompt
		PROMPT_SUCCESS=false
		while [[ "$PROMPT_SUCCESS" == false ]]; do
			read -p "Specify the order of your monitor (1 2 3..): " answer
			if [ "$(validate_input $answer)" -eq 0 ]; then
				order=($answer)
				[[ "${#list[@]}" -eq "${#order[@]}" ]] && PROMPT_SUCCESS=true
			fi
		done

		# define monitors by order
		START=1
		DESKTOPS=2
		for item in "${order[@]}"; do
			index=$((item - 1))
			end=$((START + DESKTOPS))
			define_monitor "${list[$index]}" "$START" "$end"
			START="$end"
		done
	fi
else
	define_monitor "" 1 4
fi
