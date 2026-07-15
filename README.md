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
- `MEDIA_EXTENSIONS`: Space-separated extensions (no dots) used by find across scripts
- `PHOTO_HASH_STATE_DIR`, `HASH_PIPELINE_SLUG`, `LIGHTROOM_IMPORTED_ROOT`: Optional hash registry and import index (see below)
- `PROJ_DIR`: Repo root (parent of `scripts/` and `lib/`)
- `TRAVELING_STAGING_DIR`: Fallback when i/f network drives are unmounted (default: `/mnt/c/Users/droll/framobil`)

### 4. Traveling Setup (optional)

When `LOCAL_STAGING_DIR` is on `/mnt/f` or `/mnt/i` (network drives from blacktower), those drives are typically disconnected when traveling. The scripts automatically detect unmounted drives and use `TRAVELING_STAGING_DIR` instead.

Create the traveling staging directory if needed:
```bash
mkdir -p /mnt/c/Users/droll/framobil
```

Run `bash scripts/validate_setup.sh` to verify traveling fallback is ready.

### Hash registry and import index (optional)

If **`PHOTO_HASH_STATE_DIR`** and **`HASH_PIPELINE_SLUG`** are set in `config.conf`, `copy_photos.sh` and `move_photos.sh` compute SHA-256 for transferred files, update a **per-pipeline registry**, and append a **transfer audit** log. Set **`LIGHTROOM_IMPORTED_ROOT`** (and optionally **`LIGHTROOM_IMPORTED_ROOT_EXTRA`**) for **`build_import_index.sh`**, which walks those directories (using **`MEDIA_EXTENSIONS`**) and registers hashes with `source=import`. Nothing in these scripts reads or writes a Lightroom **catalog** (`.lrcat`).

- **Isolation:** Use a different slug or state parent per workflow (e.g. phone vs camera) so registries never mix.
- **On disk:** `$PHOTO_HASH_STATE_DIR/$HASH_PIPELINE_SLUG/registry_known.tsv` and `audit/transfer_audit_YYYY_<slug>.csv` (tab-separated rows for safe paths).
- **Move:** If a file’s hash is already in the registry after copy, the device file is **not** deleted (avoids removing the only instance when the file is already in the indexed import tree).
- **Logs:** `copy_log_*.csv` / `move_log_*.csv` are unchanged; audit/registry add per-file detail. Old runs are not backfilled.

First run: set variables, `bash scripts/validate_setup.sh`, then:

```bash
bash scripts/build_import_index.sh
```

…once per import tree, then use copy/move with the same slug.

## Usage

### Basic Photo Copy
```bash
bash scripts/copy_photos.sh
```
- Select folders to process
- Choose from 8 date filtering options (All files, Since last copy, Date ranges, Today, Yesterday, Last 7 days)
- Copy photos from device to staging area
- Automatically skips existing files

### Date Filtering

All scripts now use consistent date filtering options with clear inclusivity/exclusivity:

- **Option 1**: All files
- **Option 2**: Since last copy — uses the last line of **`COPY_LOG`** (same timestamp field as `copy_photos.sh` option 2)
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
bash scripts/move_photos.sh
```
- Copies photos AND deletes them from phone after successful transfer
- Best for freeing up phone storage immediately

#### Option 2: Copy First, Then Clean Up Later
```bash
# Step 1: Copy photos
bash scripts/copy_photos.sh

# Step 2: Clean up phone storage (after verifying copy success)
bash scripts/delete_already_copied_photos.sh
```
- Safer approach - copy first, verify, then delete
- Good for when you want to double-check before deleting

### Device overview and duplicate check
```bash
bash scripts/overview_device_photos.sh
# Or target a folder by name, e.g. Album Adidas (under DCIM or Pictures):
bash scripts/overview_device_photos.sh Adidas
```
- Lists folders in `DEVICE_PHOTO_DIR` (DCIM) and optionally `DEVICE_PICTURES_DIR` (Pictures)
- Pick a folder to see total file count and **duplicate analysis by file size**
- Same-size files are reported as possible duplicates (for certainty, use a hash-based tool later)

### Cross-folder duplicate cleanup (Adidas / by filename)
```bash
bash scripts/find_cross_folder_duplicates.sh
```
- **Target folder** (e.g. Adidas): files here are compared by **filename** to reference folders (e.g. DCIM).
- **Duplicates** (same name in reference): listed in `logs/duplicates_to_remove.txt`; script can **delete** them on the device.
- **Non-duplicates**: script can **move** them out of the target folder to a destination (e.g. parent folder).
- Configure `CROSS_DUP_TARGET_DIR`, `CROSS_DUP_REFERENCE_DIRS` in `config.conf` if needed.
- **Move rules in the script**: When you apply cleanup, you define **one pattern at a time** and its **destination folder** (e.g. `IMG*` → OpenCamera, `VID*` → OpenCamera, `Screenshot*` → Screenshots). Empty pattern to finish. Files not matching any pattern stay in the target folder.
- **Redmi/Xiaomi Gallery**: Photos are under `Pictures/Gallery`. Album folder names often have a **trailing space** (e.g. `Adidas `, `owner `). The script tries the path with trailing space automatically if it finds 0 files; you can also set `CROSS_DUP_TARGET_DIR` to the exact path (including the space) in config.
- After the report you are prompted: *Apply cleanup? Delete duplicates and move non-duplicates (y/N)*.
- Use **`--dry-run`** (or **`-n`**) to simulate: no changes on device, but actions are written to the log.
- All delete/move actions are appended to a log file (default: `logs/cross_dup_YYYYMMDD.log`; set `CROSS_DUP_LOG` in config to override). Log lines: `delete	<path>` or `move	<path>	<dest>` (dry-run uses `would_delete` / `would_move`).

### SSH to phone
```bash
bash scripts/ssh_phone.sh              # Interactive shell on phone (Termux)
bash scripts/ssh_phone.sh "ls /storage/emulated/0/DCIM"   # Run a single command
```
Uses `config.conf` (DEVICE_IP, DEVICE_USER, SSH_KEY, DEVICE_PORT).

### Connection Test
```bash
bash scripts/list_device_photos.sh
```
- Verify SSH connection
- List available folders on device
- Show sample files

### Traveling Mode

When i/f mounts are unavailable, scripts automatically use `TRAVELING_STAGING_DIR`. A yellow notice indicates traveling mode is active. No extra steps needed.

### Sync After Returning Home

When back home with network drives connected, sync photos from framobil to your normal staging dir:

```bash
bash scripts/sync_traveling_photos.sh           # Copy photos to normal staging
bash scripts/sync_traveling_photos.sh --move    # Move (frees framobil after sync)
bash scripts/sync_traveling_photos.sh --dry-run # Preview what would be synced
```

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
getphotosfromphone/
├── README.md                # This file
├── config.example.conf      # Configuration template
├── config.conf              # Your settings (gitignored)
├── lib/                     # Shared libraries
│   ├── resolve_staging_dir.sh
│   ├── find_media_extensions.sh
│   └── photo_hash_state.sh
├── scripts/                 # Entry-point scripts
│   ├── copy_photos.sh
│   ├── move_photos.sh
│   ├── delete_already_copied_photos.sh
│   ├── sync_traveling_photos.sh
│   ├── build_import_index.sh
│   ├── validate_setup.sh
│   ├── list_device_photos.sh
│   ├── overview_device_photos.sh
│   ├── find_cross_folder_duplicates.sh
│   └── ssh_phone.sh
├── logs/                    # Runtime logs (gitignored)
├── old/                     # Historical docs and one-off tools
│   ├── PROJECT_TRANSFER_SANITIZED.md
│   ├── tools/
│   └── phone_scripts/
└── photo_hash_state/        # Hash registry runtime data (gitignored)
```

## Logging

Runtime logs are written under `logs/` (gitignored). Set `PROJ_DIR` in `config.conf` so log paths resolve correctly.

### Console output
- Colored status messages during script runs

### CSV and action logs (under `logs/`)
- `copy_log_YYYY.csv`: Copy operations — timestamp, action, paths, file counts
- `move_log_YYYY.csv`: Move operations
- `delete_log_YYYY.csv`: Delete-on-device operations
- `sync_log_YYYY.csv`: Traveling sync operations
- `cross_dup_YYYYMMDD.log`: Cross-folder duplicate cleanup actions
- `duplicates_to_remove.txt`: Report from cross-folder duplicate scan (regenerated each run)

Note: `summary_YYYY.txt` is defined in config but not written by any script today.

## Safety Features

- **Connection verification** before operations
- **Dry-run capabilities** to preview actions
- **User confirmation** for destructive operations
- **Existing file detection** to prevent unnecessary transfers
- **Error handling** with clear status reporting

## Workflow Examples

### Daily Photo Import
1. Run `scripts/copy_photos.sh` with "since last copy" option
2. Import new photos into Lightroom
3. Run deduplication process (separate project)
4. Clean up staging area with `delete_imported_photos.sh` (planned)

### Phone Storage Cleanup
1. Run `scripts/copy_photos.sh` to copy photos to computer
2. Verify photos copied successfully
3. Run `scripts/delete_already_copied_photos.sh` to free up phone storage

### Book Photo Processing
1. Take photos of books with phone
2. Run `scripts/copy_photos.sh` targeting Books subfolder
3. Run OCR processing script (separate project)
4. Extract ISBNs and add to Zotero (separate project)

## Planned Features

- **Move functionality**: Copy photos and delete from device in one operation ✓ (implemented)
- **Delete already copied photos** (`delete_already_copied_photos.sh`): Free phone space when files exist on PC ✓ (implemented)
- **Traveling mode**: Automatic fallback to framobil when i/f mounts unavailable ✓ (implemented)
- **Sync traveling photos**: Copy/move photos from framobil to normal staging when home ✓ (implemented)
- **Hash registry + import index**: Optional per-pipeline registry and audit (`build_import_index.sh`) ✓ (implemented)
- **Delete imported photos**: Clean up staging area after Lightroom import (planned)
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

### Traveling / Mount Issues
- If you see "Traveling mode" when at home: connect drives first (`drive_manager connect` from network/drive_manager)
- Sync script fails with "Target staging dir is on unmounted drive": ensure i/f mounts are available

## Migration (July 2026 reorganization)

If you used the repo before scripts moved under `scripts/`:

1. **`config.conf` stays at repo root** — set `PROJ_DIR` to the repo root and point log variables to `$PROJ_DIR/logs/...` (see `config.example.conf`)
2. **Run scripts from `scripts/`** — e.g. `bash scripts/copy_photos.sh` instead of `bash copy_photos.sh`
3. **Update shortcuts** — point Windows/shell shortcuts at `scripts/copy_photos.sh` (or your usual entry script)
4. **Move root-level logs into `logs/`** — `copy_log_*.csv`, `move_log_*.csv`, `delete_log_*.csv`, and `cross_dup_*.log` belong under `logs/` (not repo root)
5. **Verify:** `bash scripts/validate_setup.sh`

Hash registry and audit files under `photo_hash_state/` stay separate from transfer logs in `logs/`.

Historical material (transfer docs, one-off tools) is under `old/`.

## Contributing

This project is part of a larger photo management ecosystem. When contributing:
- Maintain modular design principles
- Preserve integration points for other workflows
- Follow existing logging and configuration patterns
- Test with actual device transfers

## License

Open source - use and modify as needed for your photo management workflows.
