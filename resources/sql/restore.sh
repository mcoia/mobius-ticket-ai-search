#!/bin/bash

# PostgreSQL Restore Script for request_tracker schema
# ---------------------------------------------------

# Database connection parameters for target PostgreSQL instance
TARGET_DB_NAME="postgres"
TARGET_DB_HOST="localhost"  # Change this to your target PostgreSQL host
TARGET_DB_USER="postgres"
TARGET_DB_PASSWORD="postgres"
SCHEMA="request_tracker"

# Backup file to restore
if [ -z "$1" ]; then
    echo "Error: No backup file specified!"
    echo "Usage: $0 /path/to/backup_file.dump"
    exit 1
fi

BACKUP_FILE=$1

# Check if backup file exists
if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

# Set PGPASSWORD environment variable
export PGPASSWORD=$TARGET_DB_PASSWORD

echo "Starting restore of $SCHEMA schema to $TARGET_DB_NAME database..."

# Create schema if it doesn't exist
psql -h $TARGET_DB_HOST -U $TARGET_DB_USER -d $TARGET_DB_NAME -c "CREATE SCHEMA IF NOT EXISTS $SCHEMA;"

# Restore using pg_restore
# -c: Clean (drop) database objects before recreating
# -n: Restore only the named schema
pg_restore -h $TARGET_DB_HOST -U $TARGET_DB_USER -d $TARGET_DB_NAME -n $SCHEMA -c --if-exists $BACKUP_FILE

# Check if restore was successful
if [ $? -eq 0 ]; then
    echo "Restore completed successfully."
else
    echo "Restore completed with warnings or errors."
fi

# Unset password environment variable for security
unset PGPASSWORD

exit 0