#!/bin/bash

display_help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -d, --distribution <distro>    Set the distribution ('arch' or 'debian')"
  echo "  --desktop                      Enable desktop mode"
	echo "  --display                      Specify display"
  echo "  --help                         Show this help message"
  echo
  echo "Example usage:"
  echo "  $0 -d debian"
	echo "  $0 -d arch --desktop"
	echo "  $0 -d arch --desktop --display 2"
  exit 0
}

# Function to validate the distribution
validate_distribution() {
  if [[ "$1" != "arch" && "$1" != "debian" ]]; then
    echo "Error: Invalid distribution. Allowed values are 'arch' or 'debian'."
    exit 1
  fi
}

# Initialize variables
DESKTOP=false
DESKTOP_DISPLAY=1
DISTRIBUTION=""

# Parse the options
while [[ $# -gt 0 ]]; do
  case $1 in
    --desktop)
      DESKTOP=true
      shift
      ;;
		--display)
			DESKTOP_DISPLAY="$2"
			shift 2
			;;
    -d|--distribution)
      DISTRIBUTION="$2"
			validate_distribution "$DISTRIBUTION"
      shift 2
      ;;
		--help) display_help ;;
    *)
      echo "Unknown option: $1"
			display_help
      exit 1
      ;;
  esac
done

if [ -n "$DISTRIBUTION" ]; then
	tag="dotfiles-$DISTRIBUTION"
	docker build -t "$tag" -f "$DISTRIBUTION.Dockerfile" .
	if [[ "$DESKTOP" == true ]]; then

		# Open Xephyr
		Xephyr -br -ac -noreset -screen 1280x720 +extension Composite ":$DESKTOP_DISPLAY" &
		XEPHYR_PID=$!
		trap "kill $XEPHYR_PID" EXIT # Close xephyr on exit

		docker run -it \
			-e DESKTOP=true \
			-e DISPLAY=":$DESKTOP_DISPLAY" \
			--net=host \
			--privileged \
			"$tag"
	else
		docker run -it "$tag"
	fi
else
  echo "No distribution specified."
	exit 1
fi
