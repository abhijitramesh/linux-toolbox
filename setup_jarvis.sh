#!/bin/bash

# Check if required arguments are provided
if [ $# -ne 2 ]; then
    echo "Please provide both the HostName and SSH connection string"
    echo "Usage: $0 <hostname> <ssh-connection-string>"
    echo "Example: $0 jarvis-gpu 'ssh -o StrictHostKeyChecking=no -p 11014 root@123.45.67.89'"
    exit 1
fi

HOSTNAME=$1
SSH_STRING=$2

# Extract port and IP from SSH string
PORT=$(echo "$SSH_STRING" | sed -n 's/.*-p \([0-9]*\).*/\1/p')
IP=$(echo "$SSH_STRING" | sed -n 's/.*@\([^[:space:]]*\).*/\1/p')

# Add after the PORT and IP extraction
echo "Extracted PORT: $PORT"
echo "Extracted IP: $IP"

# Function to update SSH config
update_ssh_config() {
    local host=$1
    local port=$2
    local ip=$3
    local config_file="$HOME/.ssh/config"
    local temp_file=$(mktemp)
    local host_found=false
    
    # Create backup of original config
    cp "$config_file" "${config_file}.backup"
    
    # Read the config file line by line
    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $line =~ ^Host[[:space:]]+$host$ ]]; then
            # Found the host block, write it and the updated values
            echo "$line" >> "$temp_file"
            echo "    HostName $ip" >> "$temp_file"
            echo "    Port $port" >> "$temp_file"
            echo "    User root" >> "$temp_file"
            echo "    ForwardAgent yes" >> "$temp_file"
            echo "    UseKeychain yes" >> "$temp_file"
            echo "    StrictHostKeyChecking no" >> "$temp_file"
            host_found=true
            
            # Skip the existing host block
            while IFS= read -r next_line; do
                if [[ $next_line =~ ^Host[[:space:]] ]] || [[ -z $next_line ]]; then
                    echo "$next_line" >> "$temp_file"
                    break
                fi
            done
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$config_file"
    
    # If host wasn't found, add it to the end
    if [ "$host_found" = false ]; then
        echo "" >> "$temp_file"
        echo "Host $host" >> "$temp_file"
        echo "    HostName $ip" >> "$temp_file"
        echo "    Port $port" >> "$temp_file"
        echo "    User root" >> "$temp_file"
        echo "    ForwardAgent yes" >> "$temp_file"
        echo "    UseKeychain yes" >> "$temp_file"
        echo "    StrictHostKeyChecking no" >> "$temp_file"
    fi
    
    # Move new config in place and set permissions
    mv "$temp_file" "$config_file"
    chmod 600 "$config_file"
}

# Update SSH config before proceeding
update_ssh_config "$HOSTNAME" "$PORT" "$IP"

# Function to extract plugins from local .zshrc
get_local_plugins() {
    local plugins=$(grep "^plugins=(" ~/.zshrc | sed 's/plugins=(//' | sed 's/)//' | tr -d '\n')
    echo "$plugins"
}

# Function to install zsh plugins
install_plugins() {
    local plugins=$1
    # Convert space-separated string to array
    IFS=' ' read -ra PLUGIN_ARRAY <<< "$plugins"
    
    for plugin in "${PLUGIN_ARRAY[@]}"; do
        # Remove quotes if present
        plugin=$(echo "$plugin" | tr -d '"' | tr -d "'")
        echo "Installing plugin: $plugin"
        git clone "https://github.com/zsh-users/$plugin.git" "${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/$plugin" 2>/dev/null || \
        echo "Plugin $plugin already exists or failed to install"
    done
}

# Create heredoc with commands to execute on remote system
ssh "$HOSTNAME" bash << 'EOC'
    # Update and upgrade system
    apt-get update
    apt-get upgrade -y

    # Install zsh
    apt-get install -y zsh

    # Install oh-my-zsh
    if [ ! -d "$HOME/.oh-my-zsh" ]; then
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi

    # Set zsh as default shell
    chsh -s $(which zsh)
EOC

# Get local plugins
LOCAL_PLUGINS=$(get_local_plugins)

# Create a temporary script to install plugins
TMP_SCRIPT=$(mktemp)
cat << EOF > "$TMP_SCRIPT"
#!/bin/bash
$(declare -f install_plugins)
install_plugins "$LOCAL_PLUGINS"

# Update .zshrc with plugins
sed -i "s/plugins=(git)/plugins=($LOCAL_PLUGINS)/" ~/.zshrc
EOF

# Copy and execute the temporary script on remote
scp "$TMP_SCRIPT" "$HOSTNAME:/tmp/install_plugins.sh"
ssh "$HOSTNAME" "bash /tmp/install_plugins.sh && rm /tmp/install_plugins.sh"

# Clean up local temporary script
rm "$TMP_SCRIPT"

# Add local bin to PATH
ssh "$HOSTNAME" "echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc"

echo "Setup completed successfully!" 