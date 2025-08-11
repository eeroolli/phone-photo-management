#!/bin/bash
# transfer_project.sh
# Generate comprehensive project transfer documentation

set -e

PROJECT_NAME="Phone Photo Management Scripts"
TRANSFER_DATE=$(date '+%Y-%m-%d %H:%M:%S')
OUTPUT_FILE="PROJECT_TRANSFER_$(date +%Y%m%d_%H%M%S).md"

cat > "$OUTPUT_FILE" << EOF
# Project Transfer: $PROJECT_NAME

**Transfer Date:** $TRANSFER_DATE  
**From:** Anthropic Default Workbench  
**To:** Moving in - Photos, Lightroom, Zotero  
**Status:** Complete and Functional

## Project Overview

Modular Bash scripts for safely transferring photos from Android devices to local staging areas via SSH. Designed as components for larger photo management workflows including Lightroom import and OCR processing.

## Current Project State

### ✅ Working Components
- **Connection Testing**: SSH connectivity verification
- **Copy Functionality**: Transfer photos without removing from device
- **Move Functionality**: Transfer photos and delete from device
- **Date Filtering**: Multiple options for selecting files by date
- **Smart Deduplication**: Automatically skips existing files
- **Comprehensive Logging**: CSV and human-readable logs
- **Modular Design**: Ready for integration with other workflows

### 📋 Project Context
This is **Component 1** of a larger ecosystem:
- **Project A**: Harddrive deduplication + Lightroom import workflow
- **Project B**: OCR for ISBN detection + Zotero integration
- **Current Project**: Phone → Computer transfer (foundational component)

## File Structure and Code

\`\`\`
Current Working Directory: /mnt/f/prog/getphotosfromphone/
├── config.conf              # Configuration (needs customization)
├── copy_photos.sh           # Copy functionality (✅ working)
├── move_photos.sh           # Move functionality (✅ working)
├── list_device_photos.sh    # Connection testing (✅ working)
├── copy_log_YYYY.csv        # Transfer logs
├── move_log_YYYY.csv        # Move operation logs
├── summary_YYYY.txt         # Human-readable summaries
├── README.md               # Documentation
└── transfer_project.sh     # This transfer script
\`\`\`

## Complete Source Code

EOF

# Add all source files to the transfer document
for file in config.conf *.sh README.md; do
    if [[ -f "$file" ]]; then
        echo "" >> "$OUTPUT_FILE"
        echo "### $file" >> "$OUTPUT_FILE"
        echo "\`\`\`bash" >> "$OUTPUT_FILE"
        cat "$file" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
        echo "\`\`\`" >> "$OUTPUT_FILE"
        echo "" >> "$OUTPUT_FILE"
    fi
done

cat >> "$OUTPUT_FILE" << EOF

## Configuration Requirements

### Essential Settings to Update
\`\`\`bash
# In config.conf - UPDATE THESE VALUES:
DEVICE_IP="192.168.1.100"           # Your phone's WiFi IP
DEVICE_USER="u0_XXX"                 # Your Termux username  
SSH_KEY="/home/username/.ssh/id_ed25519_phone"  # Your SSH key path
LOCAL_STAGING_DIR="/path/to/staging/directory"  # Where photos are copied
SCRIPT_DIR="/path/to/project/directory"  # Script location
\`\`\`

### Dependencies Required
- Bash, rsync, OpenSSH client
- Termux on Android with SSH server
- Working SSH key pair

## Current Status & Next Steps

### ✅ Completed
1. Basic copy functionality with date filtering
2. Move functionality (copy + delete from device)
3. Comprehensive error handling and logging
4. Modular design for integration
5. Connection testing and device exploration

### 🎯 Immediate Next Steps
1. **Delete functionality**: Clean up staging after Lightroom import
2. **Integration scripts**: Connect with Project A & B workflows
3. **Hash-based deduplication**: Prevent re-importing same files
4. **Enhanced date filtering**: More sophisticated selection options

### 🔗 Integration Points Ready
- \`--target subfolder\` option for specialized workflows
- \`--quiet\` mode for scripted execution
- CSV logging for analysis and integration
- Modular script design for calling from other workflows

## Testing Status

### ✅ Verified Working
- SSH connection to Android device via Termux
- File listing and folder selection
- Date-based filtering (finds correct number of files)
- Smart deduplication (skips existing files correctly)
- Comprehensive logging system

### 📝 Test Results Summary
- Connection: ✅ Working (tested multiple times)
- Copy: ✅ Working (properly skips existing files)
- Move: ✅ Working (handles case with no new files correctly)
- Logging: ✅ Working (CSV and summary logs created)

## Architecture Decisions Made

### Modular Design Philosophy
- Each script has single, focused responsibility
- Integration via command-line options, not complex interdependencies
- Centralized configuration for all scripts
- Consistent logging format across all operations

### Safety-First Approach
- Only delete from device after successful copy verification
- User confirmation for all destructive operations
- Comprehensive error handling and rollback
- Detailed logging for audit trail

## Integration Roadmap

### Project A Integration (Harddrive Cleanup)
\`\`\`bash
# Example integration pattern
bash move_photos.sh --quiet  # Get new photos
# Then run deduplication and Lightroom import
\`\`\`

### Project B Integration (OCR/Zotero)
\`\`\`bash
# Example integration pattern  
bash move_photos.sh --target Books --quiet  # Move to Books subfolder
# Then run OCR processing on Books folder
\`\`\`

## Troubleshooting Guide

### Common Issues & Solutions
1. **Connection failures**: Ensure Termux is running, sshd started
2. **Permission errors**: Check SSH key permissions (600)
3. **No files found**: Verify date filtering and folder selection
4. **Transfer failures**: Check disk space and network connectivity

## Success Metrics

This project successfully achieved its core objectives:
- ✅ Reliable photo transfer from Android to computer
- ✅ Prevention of duplicate transfers
- ✅ Safe deletion from device after verification
- ✅ Foundation for larger workflow integration
- ✅ Comprehensive logging and error handling

## Files for New Environment

All source code is included above. To recreate:

1. Create project directory
2. Copy all source files from above code blocks
3. Update config.conf with your specific settings
4. Test connection with \`bash list_device_photos.sh\`
5. Test functionality with \`bash copy_photos.sh\`

---

**Transfer Complete**: This project is ready for immediate use in the new environment with minimal setup required.

EOF

echo "Transfer document created: $OUTPUT_FILE"
echo "File size: $(ls -lh "$OUTPUT_FILE" | awk '{print $5}')"
echo ""
echo "This document contains:"
echo "- Complete project overview and status"
echo "- All source code files"
echo "- Configuration requirements"
echo "- Integration roadmap"
echo "- Troubleshooting guide"
echo ""
echo "Simply copy this document to your new Anthropic workspace."
