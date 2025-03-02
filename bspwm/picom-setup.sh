#!/bin/bash

XEPHYR=false

BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)" # Get current pwd
TEMP_DIR="$BASE_DIR/tmp/picom"
PICOM_CONFIG_FILE="$BASE_DIR/.config/picom/picom.conf"

# Parse the options
while [[ $# -gt 0 ]]; do
	case $1 in
		--xephyr)
			XEPHYR=$2
			shift 2
			;;
	esac
done

# Replace picom backend since Xephyr does not support OpenGL rendering
if [[ "$XEPHYR" == true ]]; then
	sed -i 's/^backend = "glx";$/backend = "xrender";/' "$PICOM_CONFIG_FILE"
fi
