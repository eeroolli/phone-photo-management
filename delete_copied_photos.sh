#!/bin/bash
# delete_files.sh
# Safely delete files from device based on date filtering and copy verification

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Source config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file $CONFIG_FILE not found!${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Command line options
VERIFY_COPIED=1
DRY_RUN=0
QUIET_MODE=0

while [[ $# -gt 0 ]]; do
    case $1 in
        --no-verify)
            VERIFY_COPIED=0
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --quiet)
            QUIET_MODE=1
            shift
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo "Options:"
            echo "  --no-verify    Skip verification that files exist locally"
            echo "  --dry-run      Show what would be deleted without actually deleting"
            echo "  --quiet        Minimal output"
            echo "  --help         Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Initialize delete log if needed
DELETE_LOG="${SCRIPT_DIR}/delete_log_$(date +%Y).csv"
if [[ ! -f "$DELETE_LOG" ]]; then
    echo "timestamp,action,device_folder,files_found,files_verified,files_deleted,status" > "$DELETE_LOG"
fi

echo -e "${CYAN}=== Device File Deletion Tool ===${NC}"
echo ""

# Test SSH connection
if [[ $QUIET_MODE -eq 0 ]]; then
    echo "Testing connection to device..."
fi
if ! ssh -i "$SSH_KEY" -p "$DEVICE_PORT" -o ConnectTimeout=5 "$DEVICE_USER@$DEVICE_IP" 'echo "Connection OK"' >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to device${NC}"
    echo -e "${YELLOW}Make sure Termux is running and sshd is started${NC}"
    exit 1
fi

# Get available folders
echo -e "${WHITE}Available folders on device:${NC}"
FOLDERS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -1 $DEVICE_PHOTO_DIR/" | grep -v "^\." | sort)

select folder in $FOLDERS "All"; do
    if [[ -n "$folder" ]]; then
        if [[ "$folder" == "All" ]]; then
            SELECTED_FOLDERS=($FOLDERS)
        else
            SELECTED_FOLDERS=("$folder")
        fi
        break
    else
        echo -e "${YELLOW}Please select a valid option.${NC}"
    fi
done

echo -e "${GREEN}Selected folder(s): ${SELECTED_FOLDERS[*]}${NC}"
echo ""

# Date filtering options
echo -e "${WHITE}Date filtering options:${NC}"
echo "  1) All files"
echo "  2) Files from date onwards (EXCLUDING the start date)"
echo "  3) Files before date (INCLUDING the end date)"
echo "  4) Files between two dates (EXCLUDING start, INCLUDING end)"
echo "  5) Today only (files created today)"
echo "  6) Yesterday only (files created yesterday)"
echo "  7) Last 7 days (files created in the last 7 days)"
echo ""
echo -e "${YELLOW}Note: Date filtering is based on file creation/modification time${NC}"
echo -e "${YELLOW}      'EXCLUDING' means files created on that exact date are NOT included${NC}"
echo -e "${YELLOW}      'INCLUDING' means files created on that exact date ARE included${NC}"
echo -ne "${YELLOW}Choose option [1]: ${NC}"
read date_option
[[ -z "$date_option" ]] && date_option=1

# Build date filter
DATE_FILTER=""
DATE_DESC="all files"
case $date_option in
    2)
        echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
        read start_date
        DATE_FILTER="-newermt '$start_date'"
        DATE_DESC="files created AFTER $start_date (exclusive)"
        ;;
    3)
        echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
        read end_date
        DATE_FILTER="! -newermt '$end_date'"
        DATE_DESC="files created ON or BEFORE $end_date (inclusive)"
        ;;
    4)
        echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
        read start_date
        echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
        read end_date
        DATE_FILTER="-newermt '$start_date' ! -newermt '$end_date'"
        DATE_DESC="files created AFTER $start_date AND ON or BEFORE $end_date"
        ;;
    5)
        today=$(date +%Y-%m-%d)
        tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
        DATE_FILTER="-newermt '$today' ! -newermt '$tomorrow'"
        DATE_DESC="files created today ($today)"
        ;;
    6)
        yesterday=$(date -d "yesterday" +%Y-%m-%d)
        today=$(date +%Y-%m-%d)
        DATE_FILTER="-newermt '$yesterday' ! -newermt '$today'"
        DATE_DESC="yesterday's files"
        ;;
    7)
        week_ago=$(date -d "7 days ago" +%Y-%m-%d)
        DATE_FILTER="-newermt '$week_ago'"
        DATE_DESC="files created in the last 7 days (since $week_ago)"
        ;;
esac

echo ""

# Function to check if file exists locally
file_exists_locally() {
    local device_file="$1"
    local folder="$2"
    
    # Extract filename from full path
    local filename=$(basename "$device_file")
    
    # Check in the main folder
    local local_path="$LOCAL_STAGING_DIR/$folder/$filename"
    if [[ -f "$local_path" ]]; then
        return 0
    fi
    
    # Check in any subfolders (for --target usage)
    if find "$LOCAL_STAGING_DIR/$folder" -name "$filename" -type f 2>/dev/null | grep -q .; then
        return 0
    fi
    
    return 1
}

# Process each selected folder
TOTAL_FOUND=0
TOTAL_VERIFIED=0
TOTAL_DELETED=0

for folder in "${SELECTED_FOLDERS[@]}"; do
    echo -e "${WHITE}Processing folder: $folder${NC}"
    
    DEVICE_FOLDER="$DEVICE_PHOTO_DIR/$folder"
    
    # Build find command
    FIND_CMD="find '$DEVICE_FOLDER' -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.mp4' -o -name '*.mov' \) $DATE_FILTER"
    
    # Get file list from device
    echo "Scanning for $DATE_DESC on device..."
    DEVICE_FILES=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "$FIND_CMD" | sort)
    FOLDER_FILE_COUNT=$(echo "$DEVICE_FILES" | grep -c . || echo "0")
    
    if [[ $FOLDER_FILE_COUNT -eq 0 ]]; then
        echo -e "${YELLOW}No files found in $folder matching criteria${NC}"
        echo ""
        continue
    fi
    
    echo -e "${WHITE}Found $FOLDER_FILE_COUNT files in $folder${NC}"
    TOTAL_FOUND=$((TOTAL_FOUND + FOLDER_FILE_COUNT))
    
    # Verify which files exist locally (if verification enabled)
    declare -a FILES_TO_DELETE=()
    FOLDER_VERIFIED=0
    
    if [[ $VERIFY_COPIED -eq 1 ]]; then
        echo "Verifying which files exist locally..."
        
        while IFS= read -r device_file; do
            if [[ -n "$device_file" ]]; then
                if file_exists_locally "$device_file" "$folder"; then
                    FILES_TO_DELETE+=("$device_file")
                    FOLDER_VERIFIED=$((FOLDER_VERIFIED + 1))
                fi
            fi
        done <<< "$DEVICE_FILES"
        
        echo -e "${BLUE}Files verified as copied locally: $FOLDER_VERIFIED${NC}"
        TOTAL_VERIFIED=$((TOTAL_VERIFIED + FOLDER_VERIFIED))
        
        if [[ $FOLDER_VERIFIED -eq 0 ]]; then
            echo -e "${YELLOW}No files in $folder have been copied locally - skipping deletion${NC}"
            echo ""
            continue
        fi
    else
        # No verification - add all found files to deletion list
        while IFS= read -r device_file; do
            if [[ -n "$device_file" ]]; then
                FILES_TO_DELETE+=("$device_file")
                FOLDER_VERIFIED=$((FOLDER_VERIFIED + 1))
            fi
        done <<< "$DEVICE_FILES"
        TOTAL_VERIFIED=$((TOTAL_VERIFIED + FOLDER_VERIFIED))
    fi
    
    # Show what will be deleted
    echo -e "${WHITE}Files to be deleted from $folder: ${#FILES_TO_DELETE[@]}${NC}"
    
    if [[ ${#FILES_TO_DELETE[@]} -gt 0 ]]; then
        echo "Sample files:"
        for i in "${!FILES_TO_DELETE[@]}"; do
            if [[ $i -lt 5 ]]; then
                echo "  $(basename "${FILES_TO_DELETE[$i]}")"
            fi
        done
        if [[ ${#FILES_TO_DELETE[@]} -gt 5 ]]; then
            echo "  ...and $((${#FILES_TO_DELETE[@]} - 5)) more"
        fi
    fi
    
    if [[ $DRY_RUN -eq 1 ]]; then
        echo -e "${CYAN}[DRY RUN] Would delete ${#FILES_TO_DELETE[@]} files${NC}"
    else
        # Confirm deletion
        echo ""
        echo -e "${RED}WARNING: This will permanently delete ${#FILES_TO_DELETE[@]} files from your device!${NC}"
        if [[ $VERIFY_COPIED -eq 1 ]]; then
            echo -e "${GREEN}These files have been verified as copied to your computer.${NC}"
        else
            echo -e "${YELLOW}File verification was skipped - ensure files are backed up!${NC}"
        fi
        
        echo -ne "${YELLOW}Delete these files from device? (y/N): ${NC}"
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${YELLOW}Skipped deletion for $folder${NC}"
            echo ""
            continue
        fi
        
        # Perform deletion
        echo -e "${GREEN}Deleting files from $folder...${NC}"
        FOLDER_DELETED=0
        
        for file_path in "${FILES_TO_DELETE[@]}"; do
            filename=$(basename "$file_path")
            
            if [[ $QUIET_MODE -eq 0 ]]; then
                echo -n "  Deleting: $filename ... "
            fi
            
            if ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "test -f '$file_path' && rm -f '$file_path'" 2>/dev/null; then
                FOLDER_DELETED=$((FOLDER_DELETED + 1))
                if [[ $QUIET_MODE -eq 0 ]]; then
                    echo -e "${GREEN}✓${NC}"
                fi
            else
                if [[ $QUIET_MODE -eq 0 ]]; then
                    echo -e "${RED}✗${NC}"
                fi
            fi
        done
        
        TOTAL_DELETED=$((TOTAL_DELETED + FOLDER_DELETED))
        echo -e "${GREEN}Deleted $FOLDER_DELETED files from $folder${NC}"
        
        # Log the operation
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp,delete,$DEVICE_FOLDER,$FOLDER_FILE_COUNT,$FOLDER_VERIFIED,$FOLDER_DELETED,success" >> "$DELETE_LOG"
    fi
    
    echo ""
done

# Summary
echo -e "${CYAN}=== Summary ===${NC}"
echo -e "Files found matching criteria: $TOTAL_FOUND"
if [[ $VERIFY_COPIED -eq 1 ]]; then
    echo -e "Files verified as copied locally: $TOTAL_VERIFIED"
else
    echo -e "Files selected for deletion (no verification): $TOTAL_VERIFIED"
fi

if [[ $DRY_RUN -eq 1 ]]; then
    echo -e "${CYAN}Files that would be deleted: $TOTAL_VERIFIED${NC}"
    echo -e "${CYAN}This was a dry run - no files were actually deleted${NC}"
else
    echo -e "Files actually deleted from device: $TOTAL_DELETED"
    
    if [[ $TOTAL_DELETED -lt $TOTAL_VERIFIED ]]; then
        echo -e "${YELLOW}Some files could not be deleted - check device permissions${NC}"
    fi
fi

echo ""
echo -e "${GREEN}Operation complete!${NC}"
