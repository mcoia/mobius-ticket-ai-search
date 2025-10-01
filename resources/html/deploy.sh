#!/bin/bash

# This script builds the Angular project and copies the built files to the server/public directory on the google vm.
# It also copies the rt-app.js
BUILD_DIR="dist/frontend/browser"
TARGET_DIR="../server/public"
VM_USER="ma"
VM_HOST="34.172.8.54"
VM_TARGET_PATH="/home/ma/repo"

# Navigate to the frontend directory
cd "$(dirname "$0")/frontend"

# Build the Angular project
echo "Building Angular project..."
ng build --configuration=production

# Check if the build was successful
if [ $? -ne 0 ]; then
  echo "Build failed. Exiting..."
  exit 1
fi

# Ensure target directory exists
mkdir -p "$TARGET_DIR"

# Copy the built files to the server/public directory
echo "Copying build output to $TARGET_DIR..."
cp -r "$BUILD_DIR"/* "$TARGET_DIR"

# Securely copy the server directory to the VM
echo "Transferring server directory to VM..."

rsync -avz --progress ../server "$VM_USER@$VM_HOST:$VM_TARGET_PATH"

# Check if SCP was successful
if [ $? -ne 0 ]; then
  echo "SCP transfer failed. Exiting..."
  exit 1
fi

echo "Build, copy, and SCP transfer completed successfully!"
