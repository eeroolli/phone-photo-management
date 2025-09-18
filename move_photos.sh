#!/bin/bash
# move_photos.sh
# Move photos from device to local staging area (copy + delete from device)

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

# Command line options for integration
CUSTOM_TARGET=""
QUIET_MODE=0
while [[ $# -gt 0 ]]; do
    case $1 in
        --target)
            CUSTOM_TARGET="$2"
            shift 2
            ;;
        --quiet)
            QUIET_MODE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--target subfolder] [--quiet]"
            exit 1
            ;;
    esac
done

# Test SSH connection
if [[ $QUIET_MODE -eq 0 ]]; then
    echo "Testing connection to device..."
fi
if ! ssh -i "$SSH_KEY" -p "$DEVICE_PORT" -o ConnectTimeout=5 "$DEVICE_USER@$DEVICE_IP" 'echo "Connection OK"' >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to device${NC}"
    echo -e "${YELLOW}Make sure Termux is running and sshd is started${NC}"
    exit 1
fi

# Get available folders (unless custom target specified)
if [[ -z "$CUSTOM_TARGET" ]]; then
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Available folders on device:${NC}"
    fi
    FOLDERS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -1 $DEVICE_PHOTO_DIR/" | grep -v "^\." | sort)

    if [[ $QUIET_MODE -eq 0 ]]; then
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
    else
        # In quiet mode, default to Camera
        SELECTED_FOLDERS=("Camera")
    fi
else
    # Custom target specified (for integration)
    SELECTED_FOLDERS=("Camera")  # Always source from Camera when custom target
fi

# Date filtering options
if [[ $QUIET_MODE -eq 0 ]]; then
    echo -e "${WHITE}Date filtering options:${NC}"
    echo "  1) All files"
    echo "  2) Since last copy (including last copy timestamp)"
    echo "  3) Files from date onwards (INCLUDING the start date)"
    echo "  4) Files up to date (INCLUDING the end date)"
    echo "  5) Files between two dates (INCLUDING both start and end dates)"
    echo "  6) Today only"
    echo "  7) Yesterday only"
    echo "  8) Last 7 days (INCLUDING the last 7 days up to today)"
    echo ""
    echo -e "${YELLOW}Note: All specified dates are INCLUDED in the results${NC}"
    echo -e "${YELLOW}      Date filtering is based on file modification time${NC}"
    echo -ne "${YELLOW}Choose option [2]: ${NC}"
    read date_option
    [[ -z "$date_option" ]] && date_option=2
else
    # In quiet mode, default to since last copy
    date_option=2
fi

# Build date filter part - CONSISTENT INCLUSION VERSION
DATE_FILTER=""
case $date_option in
    2)
        # Since last move - includes the exact timestamp
        if [[ -f "$MOVE_LOG" ]]; then
            LAST_MOVE=$(tail -1 "$MOVE_LOG" | cut -d',' -f1)
            if [[ -n "$LAST_MOVE" ]]; then
                DATE_FILTER="-newermt '$LAST_MOVE'"
                if [[ $QUIET_MODE -eq 0 ]]; then
                    echo -e "${BLUE}Using files since last move: $LAST_MOVE${NC}"
                fi
            fi
        fi
        ;;
    3)
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
            read start_date
            # Include files from start date onwards (INCLUDING the start date)
            DATE_FILTER="-newermt '$start_date 00:00:00'"
        fi
        ;;
    4)
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
            read end_date
            # Include files up to and INCLUDING the end date
            DATE_FILTER="! -newermt '$end_date 23:59:59'"
        fi
        ;;
    5)
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
            read start_date
            echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
            read end_date
            # Include files from start date (INCLUDING) to end date (INCLUDING)
            DATE_FILTER="-newermt '$start_date 00:00:00' ! -newermt '$end_date 23:59:59'"
        fi
        ;;
    6)
        # TODAY ONLY - Include all of today
        today=$(date +%Y-%m-%d)
        DATE_FILTER="-newermt '$today 00:00:00' ! -newermt '$today 23:59:59'"
        ;;
    7)
        # YESTERDAY ONLY - Include all of yesterday
        yesterday=$(date -d "yesterday" +%Y-%m-%d)
        DATE_FILTER="-newermt '$yesterday 00:00:00' ! -newermt '$yesterday 23:59:59'"
        ;;
    8)
        # LAST 7 DAYS - Include the last 7 days INCLUDING today
        week_ago=$(date -d "7 days ago" +%Y-%m-%d)
        DATE_FILTER="-newermt '$week_ago 00:00:00'"
        ;;
esac

# Initialize CSV log if needed
if [[ ! -f "$MOVE_LOG" ]]; then
    echo "timestamp,action,source_folder,target_folder,files_transferred,files_deleted,status" > "$MOVE_LOG"
fi

# Function to verify transfer - FIXED VERSION
verify_transfer() {
    local local_folder="$1"
    local expected_count="$2"
    local transfer_start_time="$3"
    
    # Count files that were actually copied in this session
    # Use the transfer start time as reference point
    local actual_count=$(find "$local_folder" -type f \
        \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.mp4' -o -name '*.mov' \) \
        -newermt "$transfer_start_time" 2>/dev/null | wc -l)
    
    if [[ $actual_count -ge $expected_count ]]; then
        return 0
    else
        echo -e "${RED}Warning: Expected at least $expected_count files, found $actual_count newly copied${NC}"
        return 1
    fi
}

# Process each selected folder
for folder in "${SELECTED_FOLDERS[@]}"; do
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo ""
        echo -e "${WHITE}Processing folder: $folder${NC}"
    fi
    
    DEVICE_FOLDER="$DEVICE_PHOTO_DIR/$folder"
    
    # Determine target folder
    if [[ -n "$CUSTOM_TARGET" ]]; then
        LOCAL_FOLDER="$LOCAL_STAGING_DIR/$folder/$CUSTOM_TARGET"
    else
        LOCAL_FOLDER="$LOCAL_STAGING_DIR/$folder"
    fi
    
    # Create local folder
    mkdir -p "$LOCAL_FOLDER"
    
    # Build find command with proper parentheses
    FIND_CMD="find '$DEVICE_FOLDER' -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.mp4' -o -name '*.mov' \) $DATE_FILTER"
    
    # Get file list from device
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo "Scanning files on device..."
    fi
    DEVICE_FILES=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "$FIND_CMD" | sort)
    DEVICE_FILE_COUNT=$(echo "$DEVICE_FILES" | grep -c . || echo "0")
    
    if [[ $DEVICE_FILE_COUNT -eq 0 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${YELLOW}No files found in $folder matching criteria${NC}"
        fi
        continue
    fi
    
    # Use rsync dry-run to see what would actually be copied
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo "Running rsync dry-run to check what needs to be transferred..."
    fi
    
    DRY_RUN_OUTPUT=$(rsync -av --progress --ignore-existing --dry-run \
        -e "ssh -i $SSH_KEY -p $DEVICE_PORT" \
        "$DEVICE_USER@$DEVICE_IP:$DEVICE_FOLDER/" \
        "$LOCAL_FOLDER/" 2>/dev/null || true)
    
    # Extract files that will actually be transferred
    TRANSFER_FILES=$(echo "$DRY_RUN_OUTPUT" | grep -E '\.(jpg|jpeg|png|mp4|mov)$' || true)
    FILES_TO_TRANSFER=0
    if [[ -n "$TRANSFER_FILES" && "$TRANSFER_FILES" != "" ]]; then
        FILES_TO_TRANSFER=$(echo "$TRANSFER_FILES" | wc -l)
    fi
    
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Found $DEVICE_FILE_COUNT files matching criteria on device${NC}"
        echo -e "${WHITE}Files that need to be transferred: $FILES_TO_TRANSFER${NC}"
        
        if [[ $FILES_TO_TRANSFER -eq 0 ]]; then
            echo -e "${YELLOW}All files already exist in destination. Nothing to transfer.${NC}"
            continue
        fi
        
        echo "Sample files to be moved:"
        if [[ -n "$TRANSFER_FILES" ]]; then
            echo "$TRANSFER_FILES" | head -5
            if [[ $FILES_TO_TRANSFER -gt 5 ]]; then
                echo "...and $((FILES_TO_TRANSFER - 5)) more"
            fi
        fi
        echo -e "${RED}WARNING: Files will be DELETED from phone after successful transfer!${NC}"
        
        # Confirm move
        echo -ne "${YELLOW}Move these $FILES_TO_TRANSFER files (COPY + DELETE from phone)? (y/N): ${NC}"
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Skipped $folder${NC}"
            continue
        fi
    else
        if [[ $FILES_TO_TRANSFER -eq 0 ]]; then
            continue
        fi
    fi
    
    # Record time before copy for verification
    COPY_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Step 1: Copy files
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${GREEN}Step 1: Copying $FILES_TO_TRANSFER files from $folder...${NC}"
    fi
    
    COPY_SUCCESS=0
    if rsync -av --progress --ignore-existing \
        -e "ssh -i $SSH_KEY -p $DEVICE_PORT" \
        "$DEVICE_USER@$DEVICE_IP:$DEVICE_FOLDER/" \
        "$LOCAL_FOLDER/"; then
        COPY_SUCCESS=1
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${GREEN}Copy completed successfully${NC}"
        fi
        
        # Verify transfer using the start time
        if ! verify_transfer "$LOCAL_FOLDER" "$FILES_TO_TRANSFER" "$COPY_START_TIME"; then
            echo -e "${YELLOW}Warning: Transfer verification failed, but continuing with delete operation${NC}"
        fi
    else
        echo -e "${RED}Error: Copy failed. Aborting move operation for $folder.${NC}"
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp,move,$DEVICE_FOLDER,$LOCAL_FOLDER,0,0,copy_failed" >> "$MOVE_LOG"
        continue
    fi
    
    # Step 2: Delete files from device (FIXED LOGIC)
    if [[ $COPY_SUCCESS -eq 1 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${YELLOW}Step 2: Deleting files from device...${NC}"
        fi
        
        DELETED_COUNT=0
        FAILED_DELETES=0
        
        # Create array of files to delete based on what was actually transferred
        declare -a FILES_TO_DELETE=()
        
        if [[ -n "$TRANSFER_FILES" ]]; then
            while IFS= read -r relative_path; do
                if [[ -n "$relative_path" && "$relative_path" =~ \.(jpg|jpeg|png|mp4|mov)$ ]]; then
                    # Clean up the path - remove any leading "./"
                    clean_path="${relative_path#./}"
                    full_device_path="$DEVICE_FOLDER/$clean_path"
                    FILES_TO_DELETE+=("$full_device_path")
                fi
            done <<< "$TRANSFER_FILES"
        fi
        
        # Delete each file individually with proper error handling
        for file_path in "${FILES_TO_DELETE[@]}"; do
            filename=$(basename "$file_path")
            
            if [[ $QUIET_MODE -eq 0 ]]; then
                echo -n "Deleting: $filename ... "
            fi
            
            if ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "test -f '$file_path' && rm -f '$file_path'" 2>/dev/null; then
                DELETED_COUNT=$((DELETED_COUNT + 1))
                if [[ $QUIET_MODE -eq 0 ]]; then
                    echo -e "${GREEN}✓${NC}"
                fi
            else
                FAILED_DELETES=$((FAILED_DELETES + 1))
                if [[ $QUIET_MODE -eq 0 ]]; then
                    echo -e "${RED}✗${NC}"
                    # Check if file still exists for debugging
                    if ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "test -f '$file_path'" 2>/dev/null; then
                        echo -e "${YELLOW}  → File still exists on device${NC}"
                    else
                        echo -e "${YELLOW}  → File not found (may have been already deleted)${NC}"
                    fi
                fi
            fi
        done
        
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo ""
            echo -e "${GREEN}Successfully moved $FILES_TO_TRANSFER files from $folder${NC}"
            echo -e "${GREEN}Deleted $DELETED_COUNT files from device${NC}"
            
            if [[ $FAILED_DELETES -gt 0 ]]; then
                echo -e "${YELLOW}Warning: Failed to delete $FAILED_DELETES files${NC}"
            fi
            
            if [[ $DELETED_COUNT -ne $FILES_TO_TRANSFER ]]; then
                echo -e "${YELLOW}Note: Transferred $FILES_TO_TRANSFER files, deleted $DELETED_COUNT files${NC}"
            fi
        fi
        
        # Log the operation with detailed results
        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        status="success"
        if [[ $FAILED_DELETES -gt 0 ]]; then
            status="partial_delete_failure"
        fi
        echo "$timestamp,move,$DEVICE_FOLDER,$LOCAL_FOLDER,$FILES_TO_TRANSFER,$DELETED_COUNT,$status" >> "$MOVE_LOG"
    fi
done

if [[ $QUIET_MODE -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}Move operation complete!${NC}"
    echo -e "Files moved to: $LOCAL_STAGING_DIR"
    if [[ -n "$CUSTOM_TARGET" ]]; then
        echo -e "Custom target subfolder: $CUSTOM_TARGET"
    fi
fi