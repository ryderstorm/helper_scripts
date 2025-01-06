#!/bin/bash

#===============================================================================
# This script is used to clean up and organize files in this Obsidian vault.
# It does the following:
# - Moves all Daily notes to the Dailies folder
# - Deletes any empty files titled "Untitled*"
# - Moves any images or attachments to the Attachments folder
# - Find any remaining files that are empty
#===============================================================================

set -euo pipefail

#===============================================================================
# Variables
#===============================================================================

export BLACK='\033[0;30m'
export WHITE='\033[1;37m'
export RED='\033[0;31m'
export ORANGE='\033[0;33m'
export YELLOW='\033[1;33m'
export GREEN='\033[0;32m'
export BLUE='\033[0;34m'
export CYAN='\033[0;36m'
export PURPLE='\033[0;35m'
export NC='\033[0m'
export SPACER="\n${WHITE}================================================================================${NC}\n"

#===============================================================================
# Functions
#===============================================================================

function verify_vault_dir {
  # check that the vault directory env is set
  if [ -z "${VAULT_DIR:-}" ]; then
    echo -e "${RED}Error: The VAULT_DIR environment variable is not set.${NC}"
    return 1
  fi
  # check that the vault directory exists and is accessible
  if [ ! -d "${VAULT_DIR}" ] || [ ! -r "${VAULT_DIR}" ] || [ ! -w "${VAULT_DIR}" ]; then
    echo -e "${RED}Error: The VAULT_DIR directory does not exist or is not accessible.${NC}"
    return 1
  fi
}

function move_daily_notes() {
  echo -e "${SPACER}"
  local dailies_dir="${VAULT_DIR}/Dailies"
  mkdir -p "${dailies_dir}"
  # Find any files with a name that matches the format "2024-07-01, Thursday.md"
  # and are not in the Dailies folder
  local daily_files
  daily_files=$(find . -maxdepth 1 -type f -name "????-??-??, *.md" -print0 | sort -z)
  if [ -z "$daily_files" ]; then
    echo -e "${GREEN}No Daily notes need to be moved.${NC}"
    return 0
  fi

  local daily_files_count
  daily_files_count=$(echo -n "$daily_files" | tr -cd '\0' | wc -c)
  echo -e "${YELLOW}$(echo -n "$daily_files" | tr '\0' '\n')${NC}"
  echo -e "${RED}\nFound $daily_files_count Daily notes.\n${NC}"

  if gum confirm "Move these files to the Dailies folder?"; then
    find . -maxdepth 1 -type f -name "????-??-??, *.md" -print0 | xargs -0 -I {} mv -v {} "${dailies_dir}/"
  else
    echo -e "${YELLOW}Daily notes were not moved.${NC}"
  fi
}

function delete_untitled_files() {
  echo -e "${SPACER}"
  # Find any files with a name that starts with "Untitled" and has no content
  untitled_files=$(find . -maxdepth 1 -type f -name "Untitled*" -empty | sort)
  if [ -z "$untitled_files" ]; then
    echo -e "${GREEN}No empty files found.${NC}"
  else
    untitled_files_count=$(echo "$untitled_files" | wc -l)
    echo -e "${YELLOW}$untitled_files${NC}"
    echo -e "${RED}\nFound $untitled_files_count empty files titled 'Untitled*'.\n${NC}"
    if gum confirm "Delete these files?"; then
      find . -maxdepth 1 -type f -name "Untitled*" -empty -exec rm -v {} \;

    else
      echo -e "${YELLOW}Files were not deleted.${NC}"
    fi
  fi
}

function move_attachments() {
  echo -e "${SPACER}"
  local attachments_dir="${VAULT_DIR}/Attachments"
  mkdir -p "${attachments_dir}"

  # find all files that are:
  # - not markdown files
  # - not this script
  # - in the same directory as this script
  # Using while read loop instead of command substitution to handle null bytes
  local count=0
  local file_list=""
  while IFS= read -r -d '' file; do
    ((count++))
    file_list+="${file}\n"
  done < <(find . -maxdepth 1 -type f -not -name "*.md" -not -name "$(basename "$0" 2>/dev/null)" -print0 | sort -z) || true

  if [ "$count" -eq 0 ]; then
    echo -e "${GREEN}No attachments need to be moved.${NC}"
    return 0
  fi

  echo -e "${YELLOW}${file_list}${NC}"
  echo -e "${RED}\nFound $count attachments.\n${NC}"

  if gum confirm "Move these files to the Attachments folder?"; then
    while IFS= read -r -d '' file; do
      mv -v "$file" "${attachments_dir}/" || {
        echo -e "${RED}Error moving file: $file${NC}"
        continue
      }
    done < <(find . -maxdepth 1 -type f -not -name "*.md" -not -name "$(basename "$0" 2>/dev/null)" -print0 | sort -z) || true
  else
    echo -e "${YELLOW}Attachments were not moved.${NC}"
  fi
  return 0
}

function find_empty_files() {
  echo -e "${SPACER}"
  # Find any files that are empty
  find_command_base="find . -maxdepth 2 -type f -empty"
  empty_files=$(eval "$find_command_base | sort")
  if [ -z "$empty_files" ]; then
    echo -e "${GREEN}No empty files found.${NC}"
  else
    empty_files_count=$(echo "$empty_files" | wc -l)
    echo -e "${RED}\nFound $empty_files_count empty files:\n${YELLOW}$empty_files${NC}"
    if gum confirm "Delete these files?"; then
      echo -e "${RED}Deleting empty files...${NC}"
      if eval "$find_command_base -exec rm -v {} \;"; then
        echo -e "${GREEN}Files were deleted.${NC}"
      else
        echo -e "${RED}Error deleting files.${NC}"
      fi
    else
      echo -e "${YELLOW}Files were not deleted.${NC}"
    fi
  fi
}

#===============================================================================
# Main
#===============================================================================

# Trap errors and print the line number where they occur
trap 'echo -e "${RED}Error on line ${YELLOW}$LINENO${NC}"' ERR

if ! verify_vault_dir; then
  echo -e "${RED}Exiting script.${NC}"
  exit 1
fi
echo -e "${SPACER}Running cleanup script in Obsidian vault: ${BLUE}${VAULT_DIR}${NC}"
pushd "${VAULT_DIR}" > /dev/null || exit 1
delete_untitled_files
move_daily_notes
move_attachments
find_empty_files
popd > /dev/null || true

echo -e "${SPACER}Cleanup complete.${NC}"
exit 0
