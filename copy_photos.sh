#!/bin/bash
# copy_photos.sh
# Copy photos from device to local staging area

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
NC='\033[0m'

# Source config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="$SCRIPT_DIR/config.conf"

if [ ! -f "$CONFIG_FILE" ]; then
    echo -e "${RED}Error: Config file $CONFIG_FILE not found!${NC}"
    exit 1
fi

source "$CONFIG_FILE"

# Test SSH connection
echo "Testing connection to device..."
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

# Date filtering options
echo -e "${WHITE}Date filtering options:${NC}"
echo "  1) All files"
echo "  2) Since last copy"
echo "  3) Files from date onwards (EXCLUDING the start date)"
echo "  4) Files before date (INCLUDING the end date)"
echo "  5) Files between two dates (EXCLUDING start, INCLUDING end)"
echo "  6) Today only (files created today)"
echo "  7) Yesterday only (files created yesterday)"
echo "  8) Last 7 days (files created in the last 7 days)"
echo ""
echo -e "${YELLOW}Note: Date filtering is based on file creation/modification time${NC}"
echo -e "${YELLOW}      'EXCLUDING' means files created on that exact date are NOT included${NC}"
echo -e "${YELLOW}      'INCLUDING' means files created on that exact date ARE included${NC}"
echo -ne "${YELLOW}Choose option [1]: ${NC}"
read date_option
[[ -z "$date_option" ]] && date_option=1

# Build date filter part
DATE_FILTER=""
case $date_option in
    2)
        # Since last copy - check copy log for last operation
        if [[ -f "$COPY_LOG" ]]; then
            LAST_COPY=$(tail -1 "$COPY_LOG" | cut -d',' -f1)
            if [[ -n "$LAST_COPY" ]]; then
                DATE_FILTER="-newermt '$LAST_COPY'"
                echo -e "${BLUE}Using files since last copy: $LAST_COPY${NC}"
            fi
        fi
        ;;
    3)
        echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
        read start_date
        DATE_FILTER="-newermt '$start_date'"
        ;;
    4)
        echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
        read end_date
        DATE_FILTER="! -newermt '$end_date'"
        ;;
    5)
        echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
        read start_date
        echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
        read end_date
        DATE_FILTER="-newermt '$start_date' ! -newermt '$end_date'"
        ;;
    6)
        today=$(date +%Y-%m-%d)
        tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
        DATE_FILTER="-newermt '$today' ! -newermt '$tomorrow'"
        ;;
    7)
        yesterday=$(date -d "yesterday" +%Y-%m-%d)
        today=$(date +%Y-%m-%d)
        DATE_FILTER="-newermt '$yesterday' ! -newermt '$today'"
        ;;
    8)
        week_ago=$(date -d "7 days ago" +%Y-%m-%d)
        DATE_FILTER="-newermt '$week_ago'"
        ;;
esac

# Process each selected folder
for folder in "${SELECTED_FOLDERS[@]}"; do
    echo ""
    echo -e "${WHITE}Processing folder: $folder${NC}"
    
    DEVICE_FOLDER="$DEVICE_PHOTO_DIR/$folder"
    LOCAL_FOLDER="$LOCAL_STAGING_DIR/$folder"
    
    # Create local folder
    mkdir -p "$LOCAL_FOLDER"
    
    # Build find command with proper parentheses
    FIND_CMD="find '$DEVICE_FOLDER' -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.mp4' -o -name '*.mov' \) $DATE_FILTER"
    
    # Get file list
    echo "Scanning files on device..."
    FILE_LIST=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "$FIND_CMD" | sort)
    FILE_COUNT=$(echo "$FILE_LIST" | grep -c . || echo "0")
    
    if [[ $FILE_COUNT -eq 0 ]]; then
        echo -e "${YELLOW}No files found in $folder matching criteria${NC}"
        continue
    fi
    
    echo -e "${WHITE}Found $FILE_COUNT files in $folder${NC}"
    echo "Sample files:"
    echo "$FILE_LIST" | head -5
    [[ $FILE_COUNT -gt 5 ]] && echo "...and $((FILE_COUNT - 5)) more"
    
    # Confirm copy
    echo -ne "${YELLOW}Copy these $FILE_COUNT files? (y/N): ${NC}"
    read confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${RED}Skipped $folder${NC}"
        continue
    fi
    
    # Perform copy using rsync
    echo -e "${GREEN}Copying files from $folder...${NC}"
    rsync -av --progress \
        -e "ssh -i $SSH_KEY -p $DEVICE_PORT" \
        "$DEVICE_USER@$DEVICE_IP:$DEVICE_FOLDER/" \
        "$LOCAL_FOLDER/"
    
    if [[ $? -eq 0 ]]; then
        echo -e "${GREEN}Successfully copied files from $folder${NC}"
        
        # Log the operation
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp,copy,$DEVICE_FOLDER,$LOCAL_FOLDER,$FILE_COUNT files" >> "$COPY_LOG"
    else
        echo -e "${RED}Error copying files from $folder${NC}"
    fi
done

echo ""
echo -e "${GREEN}Copy operation complete!${NC}"
echo -e "Files copied to: $LOCAL_STAGING_DIR"
