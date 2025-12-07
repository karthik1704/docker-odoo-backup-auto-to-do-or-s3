#!/bin/bash

# Load environment variables
source "$(dirname "$0")/.env"

DATE=$(date +"%Y-%m-%d_%H-%M")
BACKUP_FILE="${DB_NAME}_backup_${DATE}.zip"
FULL_BACKUP_PATH="${BACKUP_DIR}/${BACKUP_FILE}"

# Ensure backup directory exists
mkdir -p "$BACKUP_DIR"

# Get backup from Odoo via web/database/backup endpoint
echo "[INFO] Requesting backup from Odoo..."
if ! curl -X POST "${ODOO_URL}/web/database/backup" \
    -F "master_pwd=${ODOO_MASTER_PASSWORD}" \
    -F "name=${DB_NAME}" \
    -F "backup_format=zip" \
    -o "$FULL_BACKUP_PATH" \
    --fail --silent --show-error; then
    echo "[ERROR] Backup failed: curl request to Odoo failed"
    exit 1
fi

echo "[INFO] Backup created at $FULL_BACKUP_PATH"

# Upload to DigitalOcean Spaces using s3cmd
if ! s3cmd put "$FULL_BACKUP_PATH" "s3://${DO_SPACE_BUCKET}/${DO_SPACE_PATH}${BACKUP_FILE}"; then
    echo "[ERROR] Upload to DigitalOcean Spaces failed"
    exit 1
fi

echo "[INFO] Uploaded to DO Spaces"

# Delete older local backups (keep only 3)
cd "$BACKUP_DIR" || exit
ls -tp *.zip | grep -v '/$' | tail -n +4 | xargs -r rm --

# Delete older backups from DO Spaces (keep only 3)
s3cmd ls "s3://${DO_SPACE_BUCKET}/${DO_SPACE_PATH}" | \
    sort -r | awk '{print $4}' | tail -n +4 | while read -r OLD_BACKUP; do
        # Check if line is non-empty and looks like a valid S3 URL
        if [[ -n "$OLD_BACKUP" && "$OLD_BACKUP" == s3://* ]]; then
            echo "[INFO] Deleting old backup from DO Spaces: $OLD_BACKUP"
            s3cmd del "$OLD_BACKUP"
        else
            echo "[WARN] Skipping invalid or empty key: '$OLD_BACKUP'"
        fi
    done