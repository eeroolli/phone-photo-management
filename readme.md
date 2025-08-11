# Phone Photo Management Scripts

A modular collection of Bash scripts for safely transferring photos from Android devices to local staging areas via SSH, designed to integrate with larger photo management workflows including Lightroom import and OCR processing.

## Overview

This project provides reliable, interactive scripts for managing photo transfers from Android phones to computer staging directories. The scripts are designed to be modular components that can be integrated into larger workflows for photo deduplication, Lightroom import, and specialized processing (e.g., OCR for ISBN detection).

## Features

- **Modular Design**: Scripts can be used standalone or integrated into larger workflows
- **Safe Operations**: Only deletes files from device after successful transfer verification
- **Smart Filtering**: Avoid re-copying existing files, date-based filtering options
- **SSH-based Transfer**: Secure, reliable transfers via Termux on Android
- **Interactive Interface**: User-friendly prompts with colored output
- **Comprehensive Logging**: Both human-readable summaries and detailed CSV logs
- **Configurable**: Centralized configuration for easy customization

## Requirements

### On Your Computer (WSL/Linux)
- **Bash** (script environment)
- **rsync** (file transfer)
- **OpenSSH client** (SSH connectivity)
- **Standard GNU utilities**: awk, grep, sort, find, stat

Install required packages:
```bash
sudo apt-get update
sudo apt-get install bash rsync openssh-client gawk grep findutils coreutils
```

### On Your Android Phone
- **Termux** (terminal emulator - available from F-Droid)
- **OpenSSH** (SSH server)
- **rsync** (file synchronization)
- **Storage permissions** for Termux

## Setup

### 1. Phone Setup (Termux)
```bash
# In Termux on your phone
pkg update
pkg install openssh rsync
termux-setup-storage
passwd  # Set password for your user
sshd    # Start SSH daemon
whoami  # Note your username (typically u0_XXX)
```

### 2. SSH Key Setup
```bash
# On your computer
ssh-keygen -t ed25519 -f ~/.ssh/id_ed25519_phone
ssh-copy-id -i ~/.ssh/id_ed25519_phone -p 8022 u0_XXX@YOUR_PHONE_IP
```

### 3. Configuration
Create and edit `config.conf`:
```bash
cp config.example.conf config.conf
# Edit with your specific settings
```

Key settings to configure:
- `DEVICE_IP`: Your phone's WiFi IP address
- `DEVICE_USER`: Your Termux username (from `whoami`)
- `SSH_KEY`: Path to your SSH private key
- `LOCAL_STAGING_DIR`: Where photos are copied on your computer

## Usage

### Basic Photo Copy
```bash
bash copy_photos.sh
```
- Select folders to process
- Choose from 8 date filtering options (All files, Since last copy, Date ranges, Today, Yesterday, Last 7 days)
- Copy photos from device to staging area
- Automatically skips existing files

### Date Filtering

All scripts now use consistent date filtering options with clear inclusivity/exclusivity:

- **Option 1**: All files
- **Option 2**: Since last copy/operation (uses log files)
- **Option 3**: Files from date onwards (EXCLUDING the start date)
- **Option 4**: Files before date (INCLUDING the end date)  
- **Option 5**: Files between two dates (EXCLUDING start, INCLUDING end)
- **Option 6**: Today only (files created today)
- **Option 7**: Yesterday only (files created yesterday)
- **Option 8**: Last 7 days (files created in the last 7 days)

**Important**: Date filtering is based on file creation/modification time. "EXCLUDING" means files created on that exact date are NOT included, "INCLUDING" means files created on that exact date ARE included.

### Cleanup Options

#### Option 1: Copy + Delete in One Operation
```bash
bash move_photos.sh
```
- Copies photos AND deletes them from phone after successful transfer
- Best for freeing up phone storage immediately

#### Option 2: Copy First, Then Clean Up Later
```bash
# Step 1: Copy photos
bash copy_photos.sh

# Step 2: Clean up phone storage (after verifying copy success)
bash delete_copied_photos.sh
```
- Safer approach - copy first, verify, then delete
- Good for when you want to double-check before deleting

### Connection Test
```bash
bash list_device_photos.sh
```
- Verify SSH connection
- List available folders on device
- Show sample files

## Project Integration

This project is designed as a modular component for larger workflows:

### Integration Point A: Photo Deduplication & Lightroom Import
- **Purpose**: Clean computer storage and ensure Lightroom import
- **Integration**: Calls these scripts to populate staging area, then processes for deduplication and Lightroom import

### Integration Point B: OCR for ISBN Detection
- **Purpose**: Process book photos for ISBN extraction and Zotero integration
- **Integration**: Can target specific subfolders (e.g., `Camera/Books`) for specialized processing

### Modular Design Benefits
- **Separation of concerns**: Each script has a focused responsibility
- **Reusability**: Scripts can be combined in different workflows
- **Maintainability**: Easier to debug and extend individual components
- **Flexibility**: Easy to add new processing workflows

## File Structure

```
/mnt/f/prog/getphotosfromphone/
├── config.conf              # Configuration file
├── copy_photos.sh           # Main copy functionality
├── list_device_photos.sh    # Connection test and device exploration
├── move_photos.sh           # Copy + delete functionality
├── delete_copied_photos.sh  # Clean up photos from phone after copying
├── delete_imported_photos.sh # Clean up staging area after Lightroom import (planned)
├── tools/                   # Utility scripts and one-time tools
├── logs/                    # Private logs and original documents
├── copy_log_YYYY.csv        # Detailed transfer logs
├── summary_YYYY.txt         # Human-readable operation summaries
└── README.md               # This file
```

## Logging

### Human-Readable Logs
- `summary_YYYY.txt`: Operation summaries, file counts, user actions
- Console output with colored status messages

### Detailed Logs
- `copy_log_YYYY.csv`: CSV format with timestamp, action, paths, file counts
- Machine-readable for analysis and integration

## Safety Features

- **Connection verification** before operations
- **Dry-run capabilities** to preview actions
- **User confirmation** for destructive operations
- **Existing file detection** to prevent unnecessary transfers
- **Error handling** with clear status reporting

## Workflow Examples

### Daily Photo Import
1. Run `copy_photos.sh` with "since last copy" option
2. Import new photos into Lightroom
3. Run deduplication process (separate project)
4. Clean up staging area with `delete_imported_photos.sh` (planned)

### Phone Storage Cleanup
1. Run `copy_photos.sh` to copy photos to computer
2. Verify photos copied successfully
3. Run `delete_copied_photos.sh` to free up phone storage

### Book Photo Processing
1. Take photos of books with phone
2. Run `copy_photos.sh` targeting Books subfolder
3. Run OCR processing script (separate project)
4. Extract ISBNs and add to Zotero (separate project)

## Planned Features

- **Move functionality**: Copy photos and delete from device in one operation ✓ (implemented)
- **Delete copied photos**: Clean up photos from phone after copying ✓ (implemented)
- **Delete imported photos**: Clean up staging area after Lightroom import (planned)
- **Hash-based deduplication**: Integration with larger deduplication workflows
- **Subfolder targeting**: Direct photos to specific processing folders

## Troubleshooting

### Connection Issues
- Ensure Termux is running on phone
- Verify SSH daemon is started (`sshd` in Termux)
- Check phone's IP address hasn't changed
- Confirm SSH key permissions are correct

### Transfer Issues
- Verify sufficient disk space on computer
- Check file permissions in staging directories
- Ensure phone doesn't go to sleep during large transfers

## Contributing

This project is part of a larger photo management ecosystem. When contributing:
- Maintain modular design principles
- Preserve integration points for other workflows
- Follow existing logging and configuration patterns
- Test with actual device transfers

## License

Open source - use and modify as needed for your photo management workflows.
