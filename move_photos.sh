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
DEBUG_MODE=0
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
        --debug)
            DEBUG_MODE=1
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--target subfolder] [--quiet] [--debug]"
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

# Function to generate filtered file list based on date criteria
generate_filtered_file_list() {
    local folder="$1"
    local date_filter="$2"
    
    # Build find command with date filter
    local find_cmd="find '$DEVICE_PHOTO_DIR/$folder' -type f \( -name '*.jpg' -o -name '*.jpeg' -o -name '*.png' -o -name '*.mp4' -o -name '*.mov' \) $date_filter"
    
    # Get filtered list from device
    FILTERED_FILE_LIST=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "$find_cmd" | sort)
    if [[ -z "$FILTERED_FILE_LIST" ]]; then
        FILTERED_FILE_COUNT=0
    else
        FILTERED_FILE_COUNT=$(echo "$FILTERED_FILE_LIST" | wc -l)
    fi
    
    return 0
}

# Function to copy a single file
copy_single_file() {
    local device_file="$1"
    local local_file="$2"
    
    if rsync -av --progress \
        -e "ssh -i $SSH_KEY -p $DEVICE_PORT" \
        "$DEVICE_USER@$DEVICE_IP:$device_file" \
        "$local_file" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}

# Function to delete a single file from device
delete_single_file() {
    local device_file="$1"
    
    if ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "test -f '$device_file' && rm -f '$device_file'" 2>/dev/null; then
        return 0
    else
        return 1
    fi
}

# Unified function to process files with different operations
process_files_with_operation() {
    local folder="$1"
    local file_list_source="$2"  # Can be a file path or "-" for stdin
    local operation="$3"  # "copy", "move", or "dry-run"
    
    local copied_count=0
    local failed_count=0
    local deleted_count=0
    local skipped_count=0
    
    # DEBUG: Show the raw filtered list
    if [[ $DEBUG_MODE -eq 1 ]]; then
        echo "DEBUG: Reading from file: $file_list_source" >&2
        echo "DEBUG: File contents:" >&2
        cat "$file_list_source" >&2
        echo "DEBUG: End of file contents" >&2
    fi
    
    while IFS= read -r device_file <&3; do
        if [[ -n "$device_file" ]]; then
            filename=$(basename "$device_file")
            relative_path="${device_file#$DEVICE_PHOTO_DIR/$folder/}"
            local_file="$LOCAL_STAGING_DIR/$folder/$relative_path"
            
            # DEBUG OUTPUT
            if [[ $DEBUG_MODE -eq 1 ]]; then
                echo "DEBUG: device_file='$device_file'" >&2
                echo "DEBUG: filename='$filename'" >&2
                echo "DEBUG: local_file='$local_file'" >&2
                echo "DEBUG: file_exists=$([[ -f "$local_file" ]] && echo "YES" || echo "NO")" >&2
                echo "DEBUG: operation='$operation'" >&2
            fi
            
            # Check if exists locally
            if [[ -f "$local_file" ]]; then
                skipped_count=$((skipped_count + 1))
                if [[ $QUIET_MODE -eq 0 ]]; then
                    echo "Skipping: $filename (already exists)"
                fi
            else
                if [[ "$operation" == "dry-run" ]]; then
                    if [[ $QUIET_MODE -eq 0 ]]; then
                        echo "Would copy: $filename" >&2
                    fi
                    copied_count=$((copied_count + 1))
                else
                    # Actually copy file
                    if [[ $QUIET_MODE -eq 0 ]]; then
                        echo -n "Copying: $filename ... " >&2
                    fi
                    
                    if copy_single_file "$device_file" "$local_file"; then
                        copied_count=$((copied_count + 1))
                        if [[ $QUIET_MODE -eq 0 ]]; then
                            echo -e "${GREEN}✓${NC}" >&2
                        fi
                        
                        # Delete from device if move operation
                        if [[ "$operation" == "move" ]]; then
                            if [[ $QUIET_MODE -eq 0 ]]; then
                                echo -n "Deleting: $filename ... " >&2
                            fi
                            
                            if delete_single_file "$device_file"; then
                                deleted_count=$((deleted_count + 1))
                                if [[ $QUIET_MODE -eq 0 ]]; then
                                    echo -e "${GREEN}✓${NC}" >&2
                                fi
                            else
                                if [[ $QUIET_MODE -eq 0 ]]; then
                                    echo -e "${RED}✗${NC}" >&2
                                fi
                            fi
                        fi
                    else
                        failed_count=$((failed_count + 1))
                        if [[ $QUIET_MODE -eq 0 ]]; then
                            echo -e "${RED}✗${NC}" >&2
                        fi
                    fi
                fi
            fi
        fi
    done 3< "$file_list_source"
    
    # Return results for logging
    echo "$copied_count $failed_count $deleted_count $skipped_count"
}

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
    
    # Step 1: Generate filtered file list based on date criteria
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo "Scanning files on device with date filter..."
        echo "Date filter: $DATE_FILTER"
    fi
    generate_filtered_file_list "$folder" "$DATE_FILTER"
    
    if [[ $FILTERED_FILE_COUNT -eq 0 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${YELLOW}No files found in $folder matching date criteria${NC}"
        fi
        continue
    fi
    
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Found $FILTERED_FILE_COUNT files matching date criteria${NC}"
    fi
    
            # Step 2: Dry-run to show what would happen
            if [[ $QUIET_MODE -eq 0 ]]; then
                echo "Running dry-run to show what would be transferred..."
            fi
            
            # Use a temporary file to avoid subshell stdin issues
            TEMP_FILE_LIST=$(mktemp)
            echo "$FILTERED_FILE_LIST" > "$TEMP_FILE_LIST"
            DRY_RUN_RESULT=$(process_files_with_operation "$folder" "$TEMP_FILE_LIST" "dry-run")
            FILES_TO_COPY=$(echo "$DRY_RUN_RESULT" | cut -d' ' -f1)
            SKIPPED_COUNT=$(echo "$DRY_RUN_RESULT" | cut -d' ' -f4)
    
    if [[ $FILES_TO_COPY -eq 0 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${YELLOW}All filtered files already exist in destination. Nothing to transfer.${NC}"
        fi
        continue
    fi
    
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Files that need to be transferred: $FILES_TO_COPY${NC}"
        echo -e "${WHITE}Files already exist (will be skipped): $SKIPPED_COUNT${NC}"
        echo -e "${RED}WARNING: Files will be DELETED from phone after successful transfer!${NC}"
        
        # Confirm move
        echo -ne "${YELLOW}Move these $FILES_TO_COPY files (COPY + DELETE from phone)? (y/N): ${NC}"
        read confirm
        if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
            echo -e "${RED}Skipped $folder${NC}"
            continue
        fi
    fi
    
    # Record time before copy for verification
    COPY_START_TIME=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Step 3: Execute move operation (copy + delete)
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${GREEN}Step 3: Moving $FILES_TO_COPY files from $folder...${NC}"
    fi
    
    # Execute the move operation using unified processing
    # Use the same temporary file for move operation
    MOVE_RESULT=$(process_files_with_operation "$folder" "$TEMP_FILE_LIST" "move")
    COPIED_COUNT=$(echo "$MOVE_RESULT" | cut -d' ' -f1)
    FAILED_COUNT=$(echo "$MOVE_RESULT" | cut -d' ' -f2)
    DELETED_COUNT=$(echo "$MOVE_RESULT" | cut -d' ' -f3)
    SKIPPED_COUNT=$(echo "$MOVE_RESULT" | cut -d' ' -f4)
    
    # Clean up temporary file
    rm -f "$TEMP_FILE_LIST"
    
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo ""
        echo -e "${GREEN}Successfully processed $FILTERED_FILE_COUNT filtered files from $folder${NC}"
        echo -e "${GREEN}Transferred $COPIED_COUNT files, deleted $DELETED_COUNT files from device${NC}"
        echo -e "${GREEN}Skipped $SKIPPED_COUNT files (already exist)${NC}"
        
        if [[ $FAILED_COUNT -gt 0 ]]; then
            echo -e "${YELLOW}Warning: Failed to copy $FAILED_COUNT files${NC}"
        fi
        
        if [[ $DELETED_COUNT -ne $COPIED_COUNT ]]; then
            echo -e "${YELLOW}Note: Copied $COPIED_COUNT files, deleted $DELETED_COUNT files${NC}"
        fi
    fi
    
    # Log the operation with detailed results
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    status="success"
    if [[ $FAILED_COUNT -gt 0 ]]; then
        status="partial_copy_failure"
    fi
    echo "$timestamp,move,$DEVICE_FOLDER,$LOCAL_FOLDER,$COPIED_COUNT,$DELETED_COUNT,$status" >> "$MOVE_LOG"
done

if [[ $QUIET_MODE -eq 0 ]]; then
    echo ""
    echo -e "${GREEN}Move operation complete!${NC}"
    echo -e "Files moved to: $LOCAL_STAGING_DIR"
    if [[ -n "$CUSTOM_TARGET" ]]; then
        echo -e "Custom target subfolder: $CUSTOM_TARGET"
    fi
fi