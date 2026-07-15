#!/bin/bash
# delete_already_copied_photos.sh
# Delete from the device only files that already exist on the PC (staging), after optional verification.

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
WHITE='\033[1;37m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="$PROJ_DIR/config.conf"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo -e "${RED}Error: Config file $CONFIG_FILE not found!${NC}"
    exit 1
fi

source "$CONFIG_FILE"
source "$PROJ_DIR/lib/find_media_extensions.sh"
source "$PROJ_DIR/lib/resolve_staging_dir.sh"

COPY_LOG="${COPY_LOG:-$PROJ_DIR/logs/copy_log_$(date +%Y).csv}"
mkdir -p "$PROJ_DIR/logs"

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

DELETE_LOG="${DELETE_LOG:-$PROJ_DIR/logs/delete_log_$(date +%Y).csv}"
if [[ ! -f "$DELETE_LOG" ]]; then
    echo "timestamp,action,device_folder,files_found,files_verified,files_deleted,status" > "$DELETE_LOG"
fi

if [[ $QUIET_MODE -eq 0 ]]; then
    echo -e "${CYAN}=== Delete already copied (device cleanup) ===${NC}"
    echo ""
fi

if [[ $QUIET_MODE -eq 0 ]]; then
    echo "Testing connection to device..."
fi
if ! ssh -i "$SSH_KEY" -p "$DEVICE_PORT" -o ConnectTimeout=5 "$DEVICE_USER@$DEVICE_IP" 'echo "Connection OK"' >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to device${NC}"
    echo -e "${YELLOW}Make sure Termux is running and sshd is started${NC}"
    exit 1
fi

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
    echo ""
else
    SELECTED_FOLDERS=("Camera")
fi

if [[ $QUIET_MODE -eq 0 ]]; then
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
else
    date_option=1
fi

DATE_FILTER=""
DATE_DESC="all files"
case $date_option in
    2)
        if [[ ! -f "$COPY_LOG" && -f "$PROJ_DIR/copy_log_$(date +%Y).csv" ]]; then
            COPY_LOG="$PROJ_DIR/copy_log_$(date +%Y).csv"
        fi
        if [[ -f "$COPY_LOG" ]]; then
            LAST_COPY=$(tail -1 "$COPY_LOG" | cut -d',' -f1)
            if [[ -n "$LAST_COPY" ]]; then
                DATE_FILTER="-newermt '$LAST_COPY'"
                DATE_DESC="files since last copy ($LAST_COPY)"
            fi
        fi
        ;;
    3)
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
            read start_date
            DATE_FILTER="-newermt '$start_date'"
            DATE_DESC="files created AFTER $start_date (exclusive)"
        fi
        ;;
    4)
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
            read end_date
            DATE_FILTER="! -newermt '$end_date'"
            DATE_DESC="files created ON or BEFORE $end_date (inclusive)"
        fi
        ;;
    5)
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -ne "${YELLOW}Enter start date (YYYY-MM-DD): ${NC}"
            read start_date
            echo -ne "${YELLOW}Enter end date (YYYY-MM-DD): ${NC}"
            read end_date
            DATE_FILTER="-newermt '$start_date' ! -newermt '$end_date'"
            DATE_DESC="files created AFTER $start_date AND ON or BEFORE $end_date"
        fi
        ;;
    6)
        today=$(date +%Y-%m-%d)
        tomorrow=$(date -d "tomorrow" +%Y-%m-%d)
        DATE_FILTER="-newermt '$today' ! -newermt '$tomorrow'"
        DATE_DESC="files created today ($today)"
        ;;
    7)
        yesterday=$(date -d "yesterday" +%Y-%m-%d)
        today=$(date +%Y-%m-%d)
        DATE_FILTER="-newermt '$yesterday' ! -newermt '$today'"
        DATE_DESC="yesterday's files"
        ;;
    8)
        week_ago=$(date -d "7 days ago" +%Y-%m-%d)
        DATE_FILTER="-newermt '$week_ago'"
        DATE_DESC="files created in the last 7 days (since $week_ago)"
        ;;
esac

echo ""

file_exists_locally() {
    local device_file="$1"
    local folder="$2"
    local filename local_path
    filename=$(basename "$device_file")
    local_path="$LOCAL_STAGING_DIR/$folder/$filename"
    if [[ -f "$local_path" ]]; then
        return 0
    fi
    if find "$LOCAL_STAGING_DIR/$folder" -name "$filename" -type f 2>/dev/null | grep -q .; then
        return 0
    fi
    return 1
}

TOTAL_FOUND=0
TOTAL_VERIFIED=0
TOTAL_DELETED=0

for folder in "${SELECTED_FOLDERS[@]}"; do
    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Processing folder: $folder${NC}"
    fi

    DEVICE_FOLDER="$DEVICE_PHOTO_DIR/$folder"
    FIND_CMD="find '$DEVICE_FOLDER' -type f $FIND_MEDIA_INAME_PREDICATE $DATE_FILTER"

    if [[ $QUIET_MODE -eq 0 ]]; then
        echo "Scanning for $DATE_DESC on device..."
    fi
    DEVICE_FILES=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "$FIND_CMD" | sort)
    FOLDER_FILE_COUNT=$(echo "$DEVICE_FILES" | grep -c . 2>/dev/null || true)
    FOLDER_FILE_COUNT=${FOLDER_FILE_COUNT:-0}

    if [[ $FOLDER_FILE_COUNT -eq 0 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${YELLOW}No files found in $folder matching criteria${NC}"
            echo ""
        fi
        continue
    fi

    if [[ $QUIET_MODE -eq 0 ]]; then
        echo -e "${WHITE}Found $FOLDER_FILE_COUNT files in $folder${NC}"
    fi
    TOTAL_FOUND=$((TOTAL_FOUND + FOLDER_FILE_COUNT))

    declare -a FILES_TO_DELETE=()
    FOLDER_VERIFIED=0

    if [[ $VERIFY_COPIED -eq 1 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo "Verifying which files exist locally..."
        fi
        while IFS= read -r device_file; do
            if [[ -n "$device_file" ]]; then
                if file_exists_locally "$device_file" "$folder"; then
                    FILES_TO_DELETE+=("$device_file")
                    FOLDER_VERIFIED=$((FOLDER_VERIFIED + 1))
                fi
            fi
        done <<< "$DEVICE_FILES"
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${BLUE}Files verified as copied locally: $FOLDER_VERIFIED${NC}"
        fi
        TOTAL_VERIFIED=$((TOTAL_VERIFIED + FOLDER_VERIFIED))

        if [[ $FOLDER_VERIFIED -eq 0 ]]; then
            if [[ $QUIET_MODE -eq 0 ]]; then
                echo -e "${YELLOW}No files in $folder have been copied locally - skipping deletion${NC}"
                echo ""
            fi
            continue
        fi
    else
        while IFS= read -r device_file; do
            if [[ -n "$device_file" ]]; then
                FILES_TO_DELETE+=("$device_file")
                FOLDER_VERIFIED=$((FOLDER_VERIFIED + 1))
            fi
        done <<< "$DEVICE_FILES"
        TOTAL_VERIFIED=$((TOTAL_VERIFIED + FOLDER_VERIFIED))
    fi

    if [[ $QUIET_MODE -eq 0 ]]; then
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
    fi

    if [[ $DRY_RUN -eq 1 ]]; then
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${CYAN}[DRY RUN] Would delete ${#FILES_TO_DELETE[@]} files${NC}"
        fi
    else
        if [[ $QUIET_MODE -eq 0 ]]; then
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
        fi

        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${GREEN}Deleting files from $folder...${NC}"
        fi
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
        if [[ $QUIET_MODE -eq 0 ]]; then
            echo -e "${GREEN}Deleted $FOLDER_DELETED files from $folder${NC}"
        fi

        timestamp=$(date '+%Y-%m-%d %H:%M:%S')
        echo "$timestamp,delete,$DEVICE_FOLDER,$FOLDER_FILE_COUNT,$FOLDER_VERIFIED,$FOLDER_DELETED,success" >> "$DELETE_LOG"
    fi

    echo ""
done

if [[ $QUIET_MODE -eq 0 ]]; then
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
fi
