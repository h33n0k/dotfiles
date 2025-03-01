#!/bin/bash

BASE_DIR="$(cd "$(dirname "$0")" && pwd -P)" # Get current pwd
WALLPAPER="$BASE_DIR/wallpaper.jpeg"

if command -v nitrogen > /dev/null 2>&1; then
	if [ ! -f "$WALLPAPER" ]; then
		echo "Could not find wallpaper."
		echo "$WALLPAPER"
		exit 1
	fi

	if command -v xrandr > /dev/null 2>&1; then
		MONITORS=$(xrandr -q | grep " connected" | awk '{print $1}')

		i=0
		for monitor in $MONITORS; do
			nitrogen --head="$i" --set-scaled "$WALLPAPER"
			((i++))
		done

	else
		nitrogen --head=X --set-scaled "$WALLPAPER"
	fi
fi
