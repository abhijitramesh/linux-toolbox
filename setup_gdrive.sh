#!/bin/bash

# Check if rclone is installed
if ! command -v rclone &> /dev/null; then
    echo "rclone is not installed. Installing now..."
    # Install rclone using curl
    curl https://rclone.org/install.sh | sudo bash
    
    if [ $? -ne 0 ]; then
        echo "Failed to install rclone. Please install it manually."
        exit 1
    fi
fi

# Set remote name for Google Drive
REMOTE_NAME="gdrive"

# Create config directory if it doesn't exist
mkdir -p ~/.config/rclone

# Function to test connection
test_connection() {
    echo "Testing connection to Google Drive..."
    # Try to list root directory
    if rclone lsd "${REMOTE_NAME}:" > /dev/null 2>&1; then
        echo "Connection successful!"
        return 0
    else
        echo "Connection failed. Attempting to refresh authentication..."
        # Force a reauth
        rclone config reconnect "${REMOTE_NAME}:"
        return $?
    fi
}

# Check if remote already exists
if rclone listremotes | grep -q "^${REMOTE_NAME}:"; then
    echo "Remote ${REMOTE_NAME} already exists. Testing connection..."
    if ! test_connection; then
        echo "Would you like to reconfigure the remote? (y/n)"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            rclone config delete "$REMOTE_NAME"
        else
            exit 1
        fi
    else
        exit 0
    fi
fi

echo "Starting Google Drive configuration..."
echo "Please provide your Google Cloud credentials"
echo "----------------------------------------"

# Prompt for credentials
read -p "Enter your client ID (example: 123456789-xxx.apps.googleusercontent.com): " CLIENT_ID
echo ""
read -p "Enter your client secret (example: GOCSPX-xxxxxx): " CLIENT_SECRET
echo ""

# Validate inputs
if [ -z "$CLIENT_ID" ] || [ -z "$CLIENT_SECRET" ]; then
    echo "Error: Client ID and Client Secret cannot be empty"
    exit 1
fi

echo "Starting Google Drive configuration with provided credentials..."

# Configure Google Drive using rclone config with non-interactive mode
rclone config create "$REMOTE_NAME" drive \
    client_id="$CLIENT_ID" \
    client_secret="$CLIENT_SECRET" \
    config_is_local=false \
    scope=drive \
    auth_no_open_browser=true

if [ $? -ne 0 ]; then
    echo "Failed to configure Google Drive remote."
    exit 1
fi

# Test the connection after setup
if ! test_connection; then
    echo "Initial configuration completed but connection test failed."
    echo "Please verify your credentials and try again."
    exit 1
fi

echo ""
echo "Configuration completed successfully!"
echo ""
echo "You can now use rclone with Google Drive. Here are some example commands:"
echo ""
echo "List directories:"
echo "rclone lsd ${REMOTE_NAME}:"
echo ""
echo "List files:"
echo "rclone ls ${REMOTE_NAME}:"
echo ""
echo "Copy a file to Google Drive:"
echo "rclone copy /path/to/local/file ${REMOTE_NAME}:/path/to/remote"
echo ""
echo "Sync a directory:"
echo "rclone sync /path/to/local/dir ${REMOTE_NAME}:/path/to/remote/dir"
echo ""
echo "Mount Google Drive (requires rclone mount capabilities):"
echo "rclone mount ${REMOTE_NAME}: /path/to/mount/point"

# Make the script executable
chmod +x setup_gdrive.sh 