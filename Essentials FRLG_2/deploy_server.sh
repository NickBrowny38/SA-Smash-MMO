#!/bin/bash
#===============================================================================
# Pokemon Essentials Multiplayer Server Deployment Script
# Deploys server to remote SSH host
#===============================================================================

# Configuration
SERVER_HOST="46.250.245.149"
SERVER_USER="root"
SERVER_DIR="/opt/pokemon_server"
SERVER_PORT=5000

echo "=========================================="
echo "Pokemon Server Deployment Script"
echo "=========================================="
echo "Target: $SERVER_USER@$SERVER_HOST"
echo "Directory: $SERVER_DIR"
echo ""

# Upload server files
echo "[1/6] Uploading server files..."
scp multiplayer_server.rb server_config.rb server_trade_v2.rb "$SERVER_USER@$SERVER_HOST:/tmp/"

if [ $? -ne 0 ]; then
    echo "ERROR: Failed to upload files"
    exit 1
fi

echo "[2/6] Connecting to server and setting up..."

# SSH into server and run setup
ssh "$SERVER_USER@$SERVER_HOST" << 'ENDSSH'

# Create server directory
echo "[3/6] Creating server directory..."
mkdir -p /opt/pokemon_server
cd /opt/pokemon_server

# Move uploaded files
mv /tmp/multiplayer_server.rb .
mv /tmp/server_config.rb .
mv /tmp/server_trade_v2.rb .

# Make server executable
chmod +x multiplayer_server.rb

# Check if Ruby is installed
echo "[4/6] Checking Ruby installation..."
if ! command -v ruby &> /dev/null; then
    echo "Ruby not found. Installing Ruby..."

    # Detect OS and install Ruby
    if [ -f /etc/debian_version ]; then
        # Debian/Ubuntu
        apt-get update
        apt-get install -y ruby ruby-dev build-essential sqlite3 libsqlite3-dev
    elif [ -f /etc/redhat-release ]; then
        # CentOS/RHEL
        yum install -y ruby ruby-devel sqlite sqlite-devel gcc make
    else
        echo "ERROR: Unknown OS. Please install Ruby manually."
        exit 1
    fi
else
    echo "Ruby $(ruby -v) is already installed"
fi

# Install required gems
echo "[5/6] Installing required gems..."
gem install sqlite3 --no-document

# Create startup script
echo "[6/6] Creating startup script..."
cat > /opt/pokemon_server/start_server.sh << 'EOF'
#!/bin/bash
cd /opt/pokemon_server
echo "Starting Pokemon Essentials Multiplayer Server..."
echo "Port: 5000"
echo "Press Ctrl+C to stop"
ruby multiplayer_server.rb
EOF

chmod +x /opt/pokemon_server/start_server.sh

# Create systemd service for auto-restart
cat > /etc/systemd/system/pokemon-server.service << 'EOF'
[Unit]
Description=Pokemon Essentials Multiplayer Server
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/opt/pokemon_server
ExecStart=/usr/bin/ruby /opt/pokemon_server/multiplayer_server.rb
Restart=always
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Reload systemd
systemctl daemon-reload

echo ""
echo "=========================================="
echo "Deployment Complete!"
echo "=========================================="
echo ""
echo "Server installed at: /opt/pokemon_server"
echo ""
echo "To start the server manually:"
echo "  cd /opt/pokemon_server && ./start_server.sh"
echo ""
echo "To run as a service (auto-restart):"
echo "  systemctl start pokemon-server"
echo "  systemctl enable pokemon-server  # Auto-start on boot"
echo ""
echo "To view logs:"
echo "  journalctl -u pokemon-server -f"
echo ""
echo "To stop the server:"
echo "  systemctl stop pokemon-server"
echo ""
echo "Server will listen on port 5000"
echo ""

ENDSSH

echo ""
echo "=========================================="
echo "Deployment finished!"
echo "=========================================="
echo ""
echo "Next steps:"
echo "1. SSH into server: ssh $SERVER_USER@$SERVER_HOST"
echo "2. Start server: systemctl start pokemon-server"
echo "3. Check status: systemctl status pokemon-server"
echo ""
