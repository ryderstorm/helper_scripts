#!/bin/bash

# Define color codes
WHITE='\033[1;37m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'
SPACER="\n${WHITE}================================================================================${NC}\n"

# Check if convert command is available
if ! command -v convert &> /dev/null; then
  echo -e "${RED}The 'convert' command is not available. Please install ImageMagick and try again.${NC}"
  exit 1
fi

# Set default dimensions
desired_dimensions="2560x1080"

# Define usage function
usage() {
  echo "Usage: $0 [-t] [-d dimensions]"
  echo "  -t: Enable test mode (skip file conversion)"
  echo "  -d dimensions: Set desired dimensions (default: 2560x1080)"
  exit 1
}

# Parse command-line options
while getopts ":td:" opt; do
  case $opt in
    t) test_mode=1;;
    d)
      if [[ $OPTARG =~ ^[0-9]+x[0-9]+$ ]]; then
        desired_dimensions=$OPTARG
      else
        echo -e "${RED}Invalid dimensions format. Please use the format WIDTHxHEIGHT (e.g. 1920x1080).${NC}"
        exit 1
      fi
      ;;
    \?) echo "Invalid option -$OPTARG" >&2; usage;;
    :) echo "Option -$OPTARG requires an argument" >&2; usage;;
  esac
done

# Check if there are image files in the current directory
shopt -s nullglob
image_files=( *.{jpg,jpeg,png} )
if [ ${#image_files[@]} -eq 0 ]; then
  echo -e "${RED}No image files found in current directory.${NC}"
  exit 1
fi

# Set counter variables
changed_files=0
skipped_files=0
total_files=${#image_files[@]}

if [ "$test_mode" == "1" ]; then
  echo -e "${SPACER}${YELLOW}Running in test mode. No changes will be made to existing files.${NC}${SPACER}"
else
  # Create originals directory if it doesn't exist
  mkdir -p originals
fi

# Loop through image files
for image_file in "${image_files[@]}"; do
  echo -e "\n${BLUE}$image_file${NC}"
  dimensions=$(identify -format '%wx%h' "$image_file")
  if [ "$dimensions" == "$desired_dimensions" ]; then
    echo -e "${RED}Skipping image because it already has the correct dimensions of ${YELLOW}$desired_dimensions${NC}"
    skipped_files=$((skipped_files+1))
  else
    extension="${image_file##*.}"
    filename="${image_file%.*}"
    echo -e "  ${WHITE}Converting image from original dimensions ${YELLOW}$dimensions${WHITE} to ${GREEN}$desired_dimensions${NC}"
    new_filename="${filename}___resized_to_${desired_dimensions}.${extension}"
    echo -e "  ${WHITE}New filename: ${CYAN}$new_filename${NC}"
    changed_files=$((changed_files+1))
    if [ "$test_mode" != "1" ]; then
      convert "$image_file" -resize "$desired_dimensions" -background black -gravity center -extent "$desired_dimensions" "$new_filename"
      mv "$image_file" "originals/$image_file"
    fi
  fi
done

echo -e "${SPACER}"
echo -e "${YELLOW}Summary:${NC}"
echo -e "${BLUE}Total files:${NC} $total_files"
echo -e "${GREEN}Changed files:${NC} $changed_files"
echo -e "${CYAN}Skipped files:${NC} $skipped_files"
