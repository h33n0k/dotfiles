#!/bin/bash

display_help() {
  echo "Usage: $0 [OPTIONS]"
  echo
  echo "Options:"
  echo "  -d, --distribution <distro>    Set the distribution ('arch' or 'debian')"
  echo "  --desktop                      Enable desktop mode"
  echo "  --help                         Show this help message"
  echo
  echo "Example usage:"
  echo "  $0 -d debian"
	echo "  $0 -d arch --desktop"
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
DISTRIBUTION=""

# Parse the options
while [[ $# -gt 0 ]]; do
  case $1 in
    --desktop)
      DESKTOP=true
      shift
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
	docker run --rm -it "$tag"
else
  echo "No distribution specified."
	exit 1
fi
