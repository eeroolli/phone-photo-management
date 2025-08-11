#!/bin/bash
# list_device_photos.sh
# Simple script to test connection and list available photos

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
    echo "Please copy config.example.conf to config.conf and customize it"
    exit 1
fi

source "$CONFIG_FILE"

echo -e "${CYAN}=== Device Photo Explorer ===${NC}"
echo ""

# Test SSH connection
echo -e "${WHITE}Testing connection to device...${NC}"
if ! ssh -i "$SSH_KEY" -p "$DEVICE_PORT" -o ConnectTimeout=5 "$DEVICE_USER@$DEVICE_IP" 'echo "Connection OK"' >/dev/null 2>&1; then
    echo -e "${RED}Error: Cannot connect to device${NC}"
    echo -e "${YELLOW}Make sure Termux is running and sshd is started${NC}"
    echo -e "${YELLOW}Check your config.conf settings${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Connection successful!${NC}"
echo ""

# List available folders
echo -e "${WHITE}Available folders on device:${NC}"
FOLDERS=$(ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -1 $DEVICE_PHOTO_DIR/" | grep -v "^\." | sort)

if [[ -n "$FOLDERS" ]]; then
    echo "$FOLDERS"
    echo ""
    
    # Show sample files from Camera folder if it exists
    if echo "$FOLDERS" | grep -q "Camera"; then
        echo -e "${WHITE}Sample files in Camera folder:${NC}"
        ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "ls -la $DEVICE_PHOTO_DIR/Camera/ | head -10"
        echo ""
        
        # Count files by type
        echo -e "${WHITE}File count by type in Camera:${NC}"
        ssh -i "$SSH_KEY" -p "$DEVICE_PORT" "$DEVICE_USER@$DEVICE_IP" "cd $DEVICE_PHOTO_DIR/Camera && echo 'JPG/JPEG: ' \$(find . -name '*.jpg' -o -name '*.jpeg' | wc -l) && echo 'PNG: ' \$(find . -name '*.png' | wc -l) && echo 'MP4: ' \$(find . -name '*.mp4' | wc -l) && echo 'MOV: ' \$(find . -name '*.mov' | wc -l)"
    fi
else
    echo -e "${YELLOW}No folders found in $DEVICE_PHOTO_DIR${NC}"
fi

echo ""
echo -e "${GREEN}Device exploration complete!${NC}"
echo -e "Use copy_photos.sh or move_photos.sh to transfer files"
