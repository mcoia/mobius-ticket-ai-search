#!/bin/bash

# PostgreSQL Backup Script for request_tracker schema
# ----------------------------------------------------

# Database connection parameters
DB_NAME="postgres"
DB_HOST="localhost"
DB_USER="postgres"
DB_PASSWORD="postgres"
SCHEMA="request_tracker"

# Backup file details
BACKUP_DIR="./pg_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/${SCHEMA}_backup_${TIMESTAMP}.dump"

# Create backup directory if it doesn't exist
mkdir -p "$BACKUP_DIR"

# Set PGPASSWORD environment variable
export PGPASSWORD=$DB_PASSWORD

echo "Starting backup of $SCHEMA schema from $DB_NAME database..."

# Run pg_dump with custom format (-Fc) to create a compressed backup
pg_dump -h $DB_HOST -U $DB_USER -d $DB_NAME -n $SCHEMA -Fc -f $BACKUP_FILE

# Check if backup was successful
if [ $? -eq 0 ]; then
    echo "Backup completed successfully: $BACKUP_FILE"
    echo "File size: $(du -h $BACKUP_FILE | cut -f1)"
else
    echo "Backup failed!"
fi

# Unset password environment variable for security
unset PGPASSWORD

exit 0