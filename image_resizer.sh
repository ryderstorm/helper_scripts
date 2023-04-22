#!/bin/bash
WHITE='\033[1;37m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'


desired_dimensions="2560x1080"
mkdir -p originals
for image_file in *.{jpg,jpeg,png}; do
  echo -e "\n${BLUE}$image_file${NC}"
  dimensions=$(identify -format '%wx%h' "$image_file")
  if [ "$dimensions" == "$desired_dimensions" ]; then
    echo -e "${RED}Skipping image because it already has the correct dimensions of ${YELLOW}$desired_dimensions${NC}"
  else
    extension="${image_file##*.}"
    filename="${image_file%.*}"
    echo -e "  ${WHITE}Converting image from original dimensions ${YELLOW}$dimensions${WHITE} to ${GREEN}$desired_dimensions${NC}"
    new_filename="${filename}___resized_to_${desired_dimensions}.${extension}"
    echo -e "  ${WHITE}New filename: ${CYAN}$new_filename${NC}"
    if [ "$1" == "test" ]; then
      echo -e "${YELLOW}Skipping file conversion in test mode${NC}"
    else
      convert "$image_file" -resize "$desired_dimensions" -background black -gravity center -extent "$desired_dimensions" "$new_filename"
      mv "$image_file" "originals/$image_file"
    fi
  fi
done
