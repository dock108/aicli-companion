# Claude Companion Server - Production Deployment Guide

## Overview

This comprehensive guide covers deploying the Claude Companion Server in production environments. It includes configuration, security hardening, performance optimization, monitoring, and operational best practices for maintaining a reliable AI assistance platform.

## Prerequisites

### System Requirements
- **OS**: Ubuntu 20.04+ / Debian 11+ / RHEL 8+ / macOS 12+
- **CPU**: 2+ cores (4+ recommended)
- **RAM**: 4GB minimum (8GB+ recommended)
- **Storage**: 20GB+ free space
- **Network**: Stable internet connection

### Software Requirements
- **Node.js**: 18.0+ (LTS recommended)
- **npm**: 9.0+
- **AICLI**: Latest version installed and configured
- **PM2**: Process manager for Node.js
- **nginx**: 1.18+ (reverse proxy)
- **Git**: For deployment and updates

### Optional Requirements
- **Redis**: For distributed session storage (future)
- **Docker**: For containerized deployment
- **SSL Certificates**: For HTTPS (Let's Encrypt recommended)
- **APNs Certificates**: For iOS push notifications
- **Monitoring**: Datadog, New Relic, or Prometheus

## Environment Configuration

### Production Environment Variables

Create a comprehensive `.env.production` file:

```bash
# ====================
# Core Configuration
# ====================

# Server Settings
NODE_ENV=production
PORT=3001
HOST=0.0.0.0

# Authentication
AUTH_REQUIRED=true
AUTH_TOKEN=your-secure-auth-token-here  # Generate with: openssl rand -hex 32

# TLS/SSL
ENABLE_TLS=true
TLS_CERT_PATH=/etc/letsencrypt/live/yourdomain.com/fullchain.pem
TLS_KEY_PATH=/etc/letsencrypt/live/yourdomain.com/privkey.pem

# ====================
# AICLI Configuration
# ====================

# Executable Path
CLAUDE_EXECUTABLE_PATH=/usr/local/bin/claude
# Alternative names
AICLI_EXECUTABLE_NAMES=claude,aicli

# Permissions
CLAUDE_SKIP_PERMISSIONS=false
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit,Bash

# Project Directory
CONFIG_PATH=/home/claude-companion/projects

# Claude Configuration
CLAUDE_EXECUTABLE_PATH=/usr/local/bin/claude

# ====================
# Service Discovery
# ====================

ENABLE_BONJOUR=false  # Disable in production

# ====================
# Push Notifications
# ====================

# iOS Push Notifications
ENABLE_PUSH_NOTIFICATIONS=true
APNS_PRODUCTION=true
APNS_CERT_PATH=/etc/claude-companion/certs/apns-cert.pem
APNS_KEY_PATH=/etc/claude-companion/certs/apns-key.pem
APNS_PASSPHRASE=your-secure-passphrase
APNS_BUNDLE_ID=com.yourcompany.claudecompanion
APNS_TOPIC=com.yourcompany.claudecompanion

# Push Notification Settings
PUSH_RETRY_ATTEMPTS=3
PUSH_RETRY_DELAY=1000  # ms
PUSH_BATCH_SIZE=100
PUSH_RATE_LIMIT=100  # per hour per device

# ====================
# Session Management
# ====================

SESSION_TIMEOUT=86400000              # 24 hours
MAX_SESSIONS_PER_CLIENT=5             # Per device
MAX_TOTAL_SESSIONS=100                # Global limit
SESSION_CLEANUP_INTERVAL=3600000      # 1 hour
SESSION_PERSISTENCE_ENABLED=true      # Save to disk
SESSION_PERSISTENCE_PATH=/var/lib/claude-companion/sessions
SESSION_DEDUPLICATION_WINDOW=300000   # 5 minutes

# ====================
# WebSocket Configuration
# ====================

WS_HEARTBEAT_INTERVAL=30000           # 30 seconds
WS_HEARTBEAT_TIMEOUT=60000            # 1 minute
WS_CONNECTION_TIMEOUT=60000           # 1 minute
WS_RECONNECTION_WINDOW=300000         # 5 minutes
MAX_WEBSOCKET_CONNECTIONS=1000        # Per server
WS_MAX_PAYLOAD=1048576                # 1MB
WS_COMPRESSION_ENABLED=true           # permessage-deflate
WS_COMPRESSION_THRESHOLD=1024         # 1KB

# ====================
# Message Queue
# ====================

MESSAGE_QUEUE_ENABLED=true
MESSAGE_QUEUE_MAX_SIZE=1000           # Per session
MESSAGE_QUEUE_MAX_MEMORY=104857600    # 100MB total
MESSAGE_RETENTION_PERIOD=3600000      # 1 hour
MESSAGE_DELIVERY_TIMEOUT=30000        # 30 seconds
MESSAGE_DELIVERY_RETRIES=3
MESSAGE_VALIDATION_ENABLED=true       # Filter empty messages

# ====================
# Telemetry & Monitoring
# ====================

TELEMETRY_ENABLED=true
TELEMETRY_RETENTION_PERIOD=604800000  # 7 days
TELEMETRY_SAMPLING_RATE=1.0          # 100%
TELEMETRY_EXPORT_INTERVAL=300000     # 5 minutes
METRICS_PORT=9090                     # Prometheus metrics

# External Monitoring (optional)
DATADOG_API_KEY=your-datadog-key
DATADOG_APP_KEY=your-datadog-app-key
SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id

# ====================
# Connection State Management
# ====================

CONNECTION_STATE_STORAGE=file        # memory, redis, file
CONNECTION_STATE_PATH=/var/lib/claude-companion/connections
CONNECTION_STATE_TTL=86400000        # 24 hours
CONNECTION_STATE_CLEANUP_INTERVAL=3600000  # 1 hour

# Redis Configuration (if using redis storage)
REDIS_URL=redis://localhost:6379
REDIS_PASSWORD=your-redis-password
REDIS_DB=0
REDIS_KEY_PREFIX=claude:

# ====================
# Performance & Limits
# ====================

# Rate Limiting
RATE_LIMIT_ENABLED=true
RATE_LIMIT_WINDOW=60000               # 1 minute
RATE_LIMIT_MAX_REQUESTS=1000          # Per window
RATE_LIMIT_MAX_WS_MESSAGES=600        # 10 per second

# Resource Limits
MAX_REQUEST_SIZE=10485760             # 10MB
MAX_RESPONSE_SIZE=52428800            # 50MB
REQUEST_TIMEOUT=300000                # 5 minutes
PROCESS_MEMORY_LIMIT=1073741824       # 1GB per AICLI process

# ====================
# Logging
# ====================

LOG_LEVEL=info                        # error, warn, info, debug
LOG_FORMAT=json                       # json, pretty
LOG_TO_FILE=true
LOG_FILE_PATH=/var/log/claude-companion/app.log
LOG_FILE_MAX_SIZE=104857600           # 100MB
LOG_FILE_MAX_FILES=10
LOG_INCLUDE_TIMESTAMP=true

# ====================
# Security
# ====================

# CORS
CORS_ENABLED=true
CORS_ORIGIN=https://app.claudecompanion.com
CORS_CREDENTIALS=true

# Security Headers
SECURITY_HEADERS_ENABLED=true
HSTS_MAX_AGE=31536000                 # 1 year
CSP_ENABLED=true

# Request Validation
INPUT_VALIDATION_ENABLED=true
SANITIZE_INPUTS=true
MAX_PARAMETER_LENGTH=10000
```

### Environment File Management

```bash
# Create secure environment file
sudo mkdir -p /etc/claude-companion
sudo touch /etc/claude-companion/.env.production
sudo chmod 600 /etc/claude-companion/.env.production
sudo chown claude-companion:claude-companion /etc/claude-companion/.env.production

# Edit with your production values
sudo nano /etc/claude-companion/.env.production

# Symlink for application
ln -s /etc/claude-companion/.env.production /home/claude-companion/app/.env

# Validate configuration
node -e "require('dotenv').config({ path: '.env.production' }); console.log('Config loaded successfully');"
```

## Installation

### 1. System Preparation

```bash
# Update system packages
sudo apt update && sudo apt upgrade -y

# Install required system packages
sudo apt install -y \
  build-essential \
  curl \
  git \
  python3 \
  certbot \
  python3-certbot-nginx \
  ufw \
  fail2ban \
  htop \
  iotop \
  nethogs

# Create dedicated user
sudo useradd -r -m -d /home/claude-companion -s /bin/bash claude-companion
sudo usermod -aG sudo claude-companion

# Set up directory structure
sudo mkdir -p /home/claude-companion/{app,logs,backups}
sudo mkdir -p /var/lib/claude-companion/{sessions,connections}
sudo mkdir -p /var/log/claude-companion
sudo mkdir -p /etc/claude-companion/certs

# Set permissions
sudo chown -R claude-companion:claude-companion /home/claude-companion
sudo chown -R claude-companion:claude-companion /var/lib/claude-companion
sudo chown -R claude-companion:claude-companion /var/log/claude-companion
sudo chown -R claude-companion:claude-companion /etc/claude-companion
```

### 2. Install Node.js

```bash
# Install Node.js via NodeSource repository
curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash -
sudo apt-get install -y nodejs

# Verify installation
node --version  # Should be 18.x or higher
npm --version   # Should be 9.x or higher
```

### 3. Clone and Install Application

```bash
# Switch to app user
sudo su - claude-companion

# Clone repository
cd /home/claude-companion/app
git clone https://github.com/your-username/claude-companion.git .

# Install production dependencies
cd server
npm ci --production

# Create necessary directories
mkdir -p logs sessions

# Exit back to admin user
exit
```

### 4. Install and Configure PM2

```bash
# Install PM2 globally
sudo npm install -g pm2

# Install PM2 log rotation
pm2 install pm2-logrotate
pm2 set pm2-logrotate:max_size 100M
pm2 set pm2-logrotate:retain 7
pm2 set pm2-logrotate:compress true

# Create comprehensive ecosystem file
sudo -u claude-companion bash -c 'cat > /home/claude-companion/app/ecosystem.config.js << "EOF"
module.exports = {
  apps: [{
    name: "claude-companion",
    script: "./server/src/index.js",
    cwd: "/home/claude-companion/app",
    instances: 1,  // Single instance due to AICLI process management
    exec_mode: "fork",
    
    // Environment variables
    env: {
      NODE_ENV: "production",
      PORT: 3001
    },
    env_production: {
      NODE_ENV: "production",
      PORT: 3001
    },
    
    // Process management
    max_memory_restart: "1G",
    min_uptime: "10s",
    max_restarts: 10,
    restart_delay: 4000,
    autorestart: true,
    kill_timeout: 10000,
    
    // Node.js arguments
    node_args: [
      "--max-old-space-size=2048",
      "--optimize-for-size",
      "--max-semi-space-size=128",
      "--expose-gc"
    ],
    
    // Logging
    error_file: "/var/log/claude-companion/error.log",
    out_file: "/var/log/claude-companion/output.log",
    log_file: "/var/log/claude-companion/combined.log",
    time: true,
    merge_logs: true,
    log_type: "json",
    
    // File watching (disabled in production)
    watch: false,
    ignore_watch: ["node_modules", "logs", ".git", "sessions"],
    
    // Advanced options
    listen_timeout: 10000,
    shutdown_with_message: true,
    
    // Environment from file
    env_file: "/etc/claude-companion/.env.production"
  }]
};
EOF
'

# Start application with PM2
sudo -u claude-companion bash -c "cd /home/claude-companion/app && pm2 start ecosystem.config.js --env production"

# Save PM2 configuration
sudo -u claude-companion pm2 save

# Set up PM2 startup script
sudo pm2 startup systemd -u claude-companion --hp /home/claude-companion

# Enable PM2 service
sudo systemctl enable pm2-claude-companion
sudo systemctl start pm2-claude-companion

# Verify status
sudo -u claude-companion pm2 status
sudo -u claude-companion pm2 logs claude-companion --lines 50
```

### 5. Configure nginx Reverse Proxy

```nginx
# Create nginx configuration
sudo tee /etc/nginx/sites-available/claude-companion > /dev/null << 'EOF'
# Rate limiting
limit_req_zone $binary_remote_addr zone=claude_api:10m rate=10r/s;
limit_req_zone $binary_remote_addr zone=claude_ws:10m rate=100r/m;
limit_conn_zone $binary_remote_addr zone=claude_conn:10m;

# Upstream configuration
upstream claude_backend {
    server 127.0.0.1:3001 max_fails=3 fail_timeout=30s;
    keepalive 32;
}

# HTTP to HTTPS redirect
server {
    listen 80;
    listen [::]:80;
    server_name api.claudecompanion.com;
    
    # Let's Encrypt challenge
    location /.well-known/acme-challenge/ {
        root /var/www/letsencrypt;
    }
    
    # Redirect all other traffic to HTTPS
    location / {
        return 301 https://$server_name$request_uri;
    }
}

# HTTPS server
server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name api.claudecompanion.com;
    
    # Access logs
    access_log /var/log/nginx/claude-companion-access.log combined;
    error_log /var/log/nginx/claude-companion-error.log error;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/api.claudecompanion.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.claudecompanion.com/privkey.pem;
    ssl_trusted_certificate /etc/letsencrypt/live/api.claudecompanion.com/chain.pem;
    
    # SSL Security
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384;
    ssl_prefer_server_ciphers off;
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_session_tickets off;
    ssl_stapling on;
    ssl_stapling_verify on;
    
    # DNS resolver for OCSP stapling
    resolver 8.8.8.8 8.8.4.4 valid=300s;
    resolver_timeout 5s;

    # Security headers
    add_header X-Frame-Options "DENY" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "geolocation=(), microphone=(), camera=()" always;
    add_header Strict-Transport-Security "max-age=63072000; includeSubDomains; preload" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https:; font-src 'self'; connect-src 'self' wss://api.claudecompanion.com; frame-ancestors 'none';" always;
    
    # Remove server version
    server_tokens off;
    more_clear_headers Server;

    # Rate limiting
    limit_req zone=claude_api burst=20 nodelay;
    limit_conn claude_conn 100;
    
    # WebSocket endpoint
    location /ws {
        # Rate limiting for WebSocket
        limit_req zone=claude_ws burst=5 nodelay;
        
        # Proxy settings
        proxy_pass http://claude_backend;
        proxy_http_version 1.1;
        
        # WebSocket headers
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Device-ID $http_x_device_id;
        proxy_set_header X-Client-Version $http_x_client_version;
        
        # WebSocket timeouts
        proxy_connect_timeout 10s;
        proxy_send_timeout 86400s;
        proxy_read_timeout 86400s;
        
        # Disable buffering
        proxy_buffering off;
        tcp_nodelay on;
        
        # WebSocket frame size
        proxy_max_temp_file_size 0;
        client_body_buffer_size 10m;
        client_max_body_size 10m;
    }

    # REST API endpoints
    location / {
        # CORS preflight
        if ($request_method = 'OPTIONS') {
            add_header Access-Control-Allow-Origin $http_origin always;
            add_header Access-Control-Allow-Methods 'GET, POST, PUT, DELETE, OPTIONS' always;
            add_header Access-Control-Allow-Headers 'Authorization, Content-Type, X-Device-ID, X-Client-Version' always;
            add_header Access-Control-Allow-Credentials 'true' always;
            add_header Access-Control-Max-Age 86400 always;
            add_header Content-Length 0;
            add_header Content-Type text/plain;
            return 204;
        }
        
        # Proxy configuration
        proxy_pass http://claude_backend;
        proxy_http_version 1.1;
        
        # Headers
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_set_header X-Request-ID $request_id;
        
        # Connection settings
        proxy_set_header Connection "";
        
        # Timeouts
        proxy_connect_timeout 30s;
        proxy_send_timeout 300s;
        proxy_read_timeout 300s;
        
        # Buffering
        proxy_buffering on;
        proxy_buffer_size 4k;
        proxy_buffers 8 4k;
        proxy_busy_buffers_size 8k;
        
        # Body size
        client_max_body_size 10M;
        client_body_buffer_size 1M;
        
        # CORS headers
        add_header Access-Control-Allow-Origin $http_origin always;
        add_header Access-Control-Allow-Credentials 'true' always;
    }

    # Health check endpoint (no auth required)
    location /health {
        proxy_pass http://claude_backend/health;
        access_log off;
        
        # Cache health checks
        proxy_cache_valid 200 1s;
        proxy_cache_bypass $http_pragma $http_authorization;
    }
    
    # Metrics endpoint (internal only)
    location /metrics {
        allow 10.0.0.0/8;
        allow 172.16.0.0/12;
        allow 192.168.0.0/16;
        allow 127.0.0.1;
        deny all;
        
        proxy_pass http://claude_backend/api/telemetry;
    }
    
    # Static files (if any)
    location ~* \.(jpg|jpeg|png|gif|ico|css|js)$ {
        expires 1y;
        add_header Cache-Control "public, immutable";
    }
}
EOF

# Enable site
sudo ln -s /etc/nginx/sites-available/claude-companion /etc/nginx/sites-enabled/

# Test configuration
sudo nginx -t

# Reload nginx
sudo systemctl reload nginx
```

### 6. Set Up SSL/TLS Certificates

```bash
# Create webroot directory
sudo mkdir -p /var/www/letsencrypt
sudo chown www-data:www-data /var/www/letsencrypt

# Install Certbot
sudo apt update
sudo apt install -y certbot python3-certbot-nginx

# Obtain certificate (interactive)
sudo certbot certonly --webroot \
  -w /var/www/letsencrypt \
  -d api.claudecompanion.com \
  --email admin@claudecompanion.com \
  --agree-tos \
  --no-eff-email

# Or use nginx plugin (automatic)
sudo certbot --nginx -d api.claudecompanion.com

# Set up auto-renewal
sudo systemctl enable certbot.timer
sudo systemctl start certbot.timer

# Test renewal
sudo certbot renew --dry-run

# Add renewal hook for nginx
sudo tee /etc/letsencrypt/renewal-hooks/post/nginx.sh > /dev/null << 'EOF'
#!/bin/bash
systemctl reload nginx
EOF
sudo chmod +x /etc/letsencrypt/renewal-hooks/post/nginx.sh

# Verify certificate
openssl x509 -in /etc/letsencrypt/live/api.claudecompanion.com/cert.pem -text -noout | grep -A2 "Validity"

## Security Hardening

### 1. Configure Firewall (UFW)

```bash
# Reset firewall to defaults
sudo ufw --force reset

# Default policies
sudo ufw default deny incoming
sudo ufw default allow outgoing

# Allow SSH (adjust port if using custom SSH port)
sudo ufw allow 22/tcp comment 'SSH'

# Allow HTTP and HTTPS
sudo ufw allow 80/tcp comment 'HTTP'
sudo ufw allow 443/tcp comment 'HTTPS'

# Allow monitoring (internal only)
sudo ufw allow from 10.0.0.0/8 to any port 9090 comment 'Prometheus metrics'

# Rate limiting for SSH
sudo ufw limit ssh/tcp

# Enable firewall
sudo ufw --force enable

# Show status
sudo ufw status verbose
```

### 2. Configure Fail2ban

```bash
# Install fail2ban
sudo apt install -y fail2ban

# Create custom jail configuration
sudo tee /etc/fail2ban/jail.local > /dev/null << 'EOF'
[DEFAULT]
bantime = 3600
findtime = 600
maxretry = 5
destemail = admin@claudecompanion.com
sender = fail2ban@claudecompanion.com
action = %(action_mwl)s

[sshd]
enabled = true
port = 22
logpath = %(sshd_log)s
maxretry = 3

[nginx-http-auth]
enabled = true
port = http,https
logpath = /var/log/nginx/*error.log

[nginx-noscript]
enabled = true
port = http,https
logpath = /var/log/nginx/*access.log
maxretry = 2

[nginx-badbots]
enabled = true
port = http,https
logpath = /var/log/nginx/*access.log
maxretry = 2

[nginx-noproxy]
enabled = true
port = http,https
logpath = /var/log/nginx/*error.log
maxretry = 2
EOF

# Start and enable fail2ban
sudo systemctl enable fail2ban
sudo systemctl start fail2ban

# Check status
sudo fail2ban-client status
```

### 3. Generate and Secure Authentication Tokens

```bash
# Generate multiple secure tokens
echo "Generating secure tokens..."
AUTH_TOKEN=$(openssl rand -hex 32)
SESSION_SECRET=$(openssl rand -hex 32)
ENCRYPTION_KEY=$(openssl rand -hex 32)

# Store in secure location
sudo tee /etc/claude-companion/secrets > /dev/null << EOF
# Generated on $(date)
AUTH_TOKEN=$AUTH_TOKEN
SESSION_SECRET=$SESSION_SECRET
ENCRYPTION_KEY=$ENCRYPTION_KEY
EOF

# Secure the secrets file
sudo chmod 400 /etc/claude-companion/secrets
sudo chown claude-companion:claude-companion /etc/claude-companion/secrets

# Add to environment file
echo "" | sudo tee -a /etc/claude-companion/.env.production
echo "# Authentication" | sudo tee -a /etc/claude-companion/.env.production
echo "AUTH_TOKEN=$AUTH_TOKEN" | sudo tee -a /etc/claude-companion/.env.production
echo "SESSION_SECRET=$SESSION_SECRET" | sudo tee -a /etc/claude-companion/.env.production

# Display token for admin reference
echo "=========================================="
echo "Authentication Token: $AUTH_TOKEN"
echo "Save this token securely!"
echo "=========================================="
```

### 4. System Security Hardening

```bash
# Kernel security parameters
sudo tee /etc/sysctl.d/99-claude-companion.conf > /dev/null << 'EOF'
# Network security
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_syn_retries = 2
net.ipv4.tcp_synack_retries = 2
net.ipv4.tcp_max_syn_backlog = 4096
net.ipv4.ip_forward = 0
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.default.send_redirects = 0
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.log_martians = 1
net.ipv4.icmp_echo_ignore_broadcasts = 1
net.ipv4.icmp_ignore_bogus_error_responses = 1

# Connection limits
net.core.somaxconn = 65535
net.ipv4.tcp_max_tw_buckets = 1440000
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_keepalive_time = 300
net.ipv4.tcp_keepalive_probes = 5
net.ipv4.tcp_keepalive_intvl = 15

# File system
fs.file-max = 65535
fs.suid_dumpable = 0

# Memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
EOF

# Apply sysctl settings
sudo sysctl -p /etc/sysctl.d/99-claude-companion.conf

# Disable unnecessary services
sudo systemctl disable avahi-daemon
sudo systemctl disable cups
sudo systemctl disable bluetooth

# Set up automatic security updates
sudo apt install -y unattended-upgrades
sudo dpkg-reconfigure -plow unattended-upgrades

# Configure security limits
sudo tee /etc/security/limits.d/claude-companion.conf > /dev/null << 'EOF'
claude-companion soft nofile 65535
claude-companion hard nofile 65535
claude-companion soft nproc 32768
claude-companion hard nproc 32768
claude-companion soft memlock unlimited
claude-companion hard memlock unlimited
EOF
```

## Monitoring & Observability

### 1. Application Monitoring with PM2

```bash
# Real-time monitoring
sudo -u claude-companion pm2 monit

# View logs with formatting
sudo -u claude-companion pm2 logs claude-companion --lines 100 --format

# Show detailed process information
sudo -u claude-companion pm2 show claude-companion

# Monitor CPU and memory
sudo -u claude-companion pm2 describe claude-companion | grep -E "(memory|cpu)"

# Set up PM2 web dashboard (optional)
sudo -u claude-companion pm2 install pm2-web
sudo -u claude-companion pm2 set pm2-web:port 9615
sudo -u claude-companion pm2 set pm2-web:host 127.0.0.1
```

### 2. System Resource Monitoring

```bash
# Install comprehensive monitoring tools
sudo apt install -y \
  htop \
  iotop \
  nethogs \
  vnstat \
  sysstat \
  netdata

# Configure netdata for real-time monitoring
sudo systemctl enable netdata
sudo systemctl start netdata

# Access netdata dashboard at http://localhost:19999

# Set up resource monitoring script
sudo tee /usr/local/bin/claude-monitor > /dev/null << 'EOF'
#!/bin/bash

echo "=== Claude Companion System Monitor ==="
echo "Time: $(date)"
echo ""

echo "=== Process Status ==="
sudo -u claude-companion pm2 list

echo -e "\n=== Memory Usage ==="
free -h

echo -e "\n=== Disk Usage ==="
df -h | grep -E "(Filesystem|/)"

echo -e "\n=== Network Connections ==="
ss -tunap | grep :3001 | wc -l
echo "Active connections: $(ss -tunap | grep :3001 | wc -l)"

echo -e "\n=== nginx Status ==="
sudo systemctl status nginx --no-pager | head -n 5

echo -e "\n=== Recent Errors ==="
sudo tail -n 10 /var/log/claude-companion/error.log 2>/dev/null || echo "No recent errors"

echo -e "\n=== API Health ==="
curl -s http://localhost:3001/health | jq . 2>/dev/null || echo "Health check failed"
EOF

sudo chmod +x /usr/local/bin/claude-monitor

# Add to crontab for regular monitoring
(crontab -l 2>/dev/null; echo "*/15 * * * * /usr/local/bin/claude-monitor >> /var/log/claude-companion/monitor.log 2>&1") | crontab -
```

### 3. Centralized Log Management

```bash
# Configure comprehensive log rotation
sudo tee /etc/logrotate.d/claude-companion > /dev/null << 'EOF'
# Application logs
/var/log/claude-companion/*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 claude-companion claude-companion
    sharedscripts
    postrotate
        /usr/bin/pm2 reloadLogs
        /bin/kill -USR1 $(cat /var/run/nginx.pid 2>/dev/null) 2>/dev/null || true
    endscript
}

# PM2 logs
/home/claude-companion/.pm2/logs/*.log {
    daily
    rotate 7
    compress
    delaycompress
    missingok
    notifempty
    create 0640 claude-companion claude-companion
    sharedscripts
    postrotate
        sudo -u claude-companion pm2 reloadLogs
    endscript
}

# nginx logs
/var/log/nginx/claude-companion-*.log {
    daily
    rotate 30
    compress
    delaycompress
    missingok
    notifempty
    create 0640 www-data adm
    sharedscripts
    prerotate
        if [ -d /etc/logrotate.d/httpd-prerotate ]; then \
            run-parts /etc/logrotate.d/httpd-prerotate; \
        fi
    endscript
    postrotate
        invoke-rc.d nginx rotate >/dev/null 2>&1
    endscript
}
EOF

# Test log rotation
sudo logrotate -d /etc/logrotate.d/claude-companion

# Force immediate rotation (if needed)
sudo logrotate -f /etc/logrotate.d/claude-companion

# Set up log aggregation script
sudo tee /usr/local/bin/claude-logs > /dev/null << 'EOF'
#!/bin/bash

# Aggregate and analyze logs
LOG_DIR="/var/log/claude-companion"
OUTPUT_FILE="$LOG_DIR/daily-report-$(date +%Y%m%d).txt"

echo "Claude Companion Daily Log Report - $(date)" > "$OUTPUT_FILE"
echo "==========================================" >> "$OUTPUT_FILE"

# Error summary
echo -e "\nError Summary:" >> "$OUTPUT_FILE"
grep -i error "$LOG_DIR"/*.log | awk -F: "{print \$4}" | sort | uniq -c | sort -rn | head -20 >> "$OUTPUT_FILE"

# Request summary
echo -e "\nTop Endpoints:" >> "$OUTPUT_FILE"
awk "$7 ~ /^2/ {print \$6}" /var/log/nginx/claude-companion-access.log | sort | uniq -c | sort -rn | head -20 >> "$OUTPUT_FILE"

# Performance metrics
echo -e "\nResponse Time Stats:" >> "$OUTPUT_FILE"
awk "{sum+=\$10; count++} END {print \"Average response time: \" sum/count \" ms\"}" /var/log/nginx/claude-companion-access.log >> "$OUTPUT_FILE"

# Session statistics
echo -e "\nSession Statistics:" >> "$OUTPUT_FILE"
grep "Session created" "$LOG_DIR"/output.log | wc -l | xargs echo "Sessions created:" >> "$OUTPUT_FILE"
grep "Session expired" "$LOG_DIR"/output.log | wc -l | xargs echo "Sessions expired:" >> "$OUTPUT_FILE"

# Email report (optional)
# mail -s "Claude Companion Daily Report" admin@claudecompanion.com < "$OUTPUT_FILE"
EOF

sudo chmod +x /usr/local/bin/claude-logs

# Add to daily cron
sudo ln -s /usr/local/bin/claude-logs /etc/cron.daily/
```

### 4. Health Monitoring & Alerting

```bash
# Create comprehensive health check script
sudo tee /usr/local/bin/claude-health-check > /dev/null << 'EOF'
#!/bin/bash

# Configuration
API_URL="https://api.claudecompanion.com"
LOCAL_URL="http://localhost:3001"
ALERT_EMAIL="admin@claudecompanion.com"
SLACK_WEBHOOK="https://hooks.slack.com/services/YOUR/WEBHOOK/URL"

# Health check function
check_health() {
    local url=$1
    local name=$2
    
    response=$(curl -s -w "\n%{http_code}" --connect-timeout 5 --max-time 10 "$url/health")
    http_code=$(echo "$response" | tail -n1)
    body=$(echo "$response" | head -n-1)
    
    if [ "$http_code" -eq 200 ]; then
        echo "[OK] $name health check passed"
        return 0
    else
        echo "[FAIL] $name health check failed (HTTP $http_code)"
        return 1
    fi
}

# Check various endpoints
FAILURES=0

# Local health check
if ! check_health "$LOCAL_URL" "Local"; then
    ((FAILURES++))
fi

# Public health check
if ! check_health "$API_URL" "Public"; then
    ((FAILURES++))
fi

# Check PM2 process
if ! sudo -u claude-companion pm2 show claude-companion > /dev/null 2>&1; then
    echo "[FAIL] PM2 process not running"
    ((FAILURES++))
fi

# Check nginx
if ! systemctl is-active --quiet nginx; then
    echo "[FAIL] nginx is not running"
    ((FAILURES++))
fi

# Check disk space
DISK_USAGE=$(df -h / | awk "NR==2 {print \$5}" | sed "s/%//")
if [ "$DISK_USAGE" -gt 90 ]; then
    echo "[WARN] Disk usage is high: ${DISK_USAGE}%"
    ((FAILURES++))
fi

# Check memory
MEMORY_USAGE=$(free | awk "NR==2 {printf \"%.0f\", \$3/\$2 * 100}")
if [ "$MEMORY_USAGE" -gt 90 ]; then
    echo "[WARN] Memory usage is high: ${MEMORY_USAGE}%"
    ((FAILURES++))
fi

# Send alerts if failures detected
if [ "$FAILURES" -gt 0 ]; then
    MESSAGE="Claude Companion health check failed with $FAILURES issues at $(date)"
    
    # Email alert
    echo "$MESSAGE" | mail -s "[ALERT] Claude Companion Health Check Failed" "$ALERT_EMAIL"
    
    # Slack alert (if configured)
    if [ -n "$SLACK_WEBHOOK" ]; then
        curl -X POST -H "Content-type: application/json" \
            --data "{\"text\":\"$MESSAGE\"}" \
            "$SLACK_WEBHOOK"
    fi
    
    # Log to syslog
    logger -t claude-health "$MESSAGE"
    
    exit 1
fi

echo "[OK] All health checks passed"
exit 0
EOF

sudo chmod +x /usr/local/bin/claude-health-check

# Add to crontab
(crontab -l 2>/dev/null; echo "*/5 * * * * /usr/local/bin/claude-health-check >> /var/log/claude-companion/health.log 2>&1") | crontab -

# Set up Monit for process monitoring (optional)
sudo apt install -y monit

sudo tee /etc/monit/conf.d/claude-companion > /dev/null << 'EOF'
check process claude-companion
    matching "claude-companion"
    start program = "/bin/su - claude-companion -c "pm2 start claude-companion""
    stop program = "/bin/su - claude-companion -c "pm2 stop claude-companion""
    if cpu > 80% for 2 cycles then alert
    if memory > 1 GB for 2 cycles then alert
    if 3 restarts within 5 cycles then timeout

check host claude-api with address api.claudecompanion.com
    if failed
        port 443 protocol https
        request "/health"
        status = 200
        timeout 10 seconds
    then alert
EOF

sudo systemctl reload monit
```

## Performance Optimization

### 1. Node.js Performance Tuning

```bash
# Update PM2 configuration for optimal performance
sudo -u claude-companion pm2 set claude-companion:max_memory_restart 2G
sudo -u claude-companion pm2 set claude-companion:node_args "--max-old-space-size=2048 --optimize-for-size --max-semi-space-size=128 --expose-gc --gc-interval=100"

# Enable cluster mode for better CPU utilization (if applicable)
# Note: Only if AICLI process management allows it
# sudo -u claude-companion pm2 scale claude-companion 2

# Monitor garbage collection
sudo -u claude-companion pm2 install pm2-gc-stats

# Set up memory monitoring
sudo -u claude-companion pm2 install pm2-memory-monitor
sudo -u claude-companion pm2 set pm2-memory-monitor:threshold 1800  # MB

# Optimize V8 flags for production
cat >> /home/claude-companion/app/.env << 'EOF'

# V8 Optimizations
NODE_OPTIONS="--max-old-space-size=2048 --optimize-for-size --always-compact --use-idle-notification"
UV_THREADPOOL_SIZE=16
EOF
```

### 2. nginx Performance Optimization

```nginx
# Backup existing configuration
sudo cp /etc/nginx/nginx.conf /etc/nginx/nginx.conf.backup

# Create optimized nginx configuration
sudo tee /etc/nginx/nginx.conf > /dev/null << 'EOF'
user www-data;
worker_processes auto;
worker_rlimit_nofile 65535;
pid /run/nginx.pid;
include /etc/nginx/modules-enabled/*.conf;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # Basic Settings
    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    types_hash_max_size 2048;
    server_tokens off;
    
    # Timeouts
    keepalive_timeout 65;
    keepalive_requests 100;
    client_body_timeout 60;
    client_header_timeout 60;
    send_timeout 60;
    
    # Buffers
    client_body_buffer_size 128k;
    client_max_body_size 10m;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;
    output_buffers 1 32k;
    postpone_output 1460;
    
    # Caching
    open_file_cache max=1000 inactive=20s;
    open_file_cache_valid 30s;
    open_file_cache_min_uses 2;
    open_file_cache_errors on;
    
    # Gzip Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml application/atom+xml image/svg+xml;
    gzip_min_length 1000;
    gzip_disable "msie6";
    
    # SSL Optimization
    ssl_session_cache shared:SSL:10m;
    ssl_session_timeout 10m;
    ssl_buffer_size 8k;
    
    # Logging
    access_log /var/log/nginx/access.log combined buffer=16k flush=2m;
    error_log /var/log/nginx/error.log error;
    
    # Default MIME types
    include /etc/nginx/mime.types;
    default_type application/octet-stream;
    
    # Rate limiting zones
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;
    limit_req_zone $binary_remote_addr zone=ws_limit:10m rate=100r/m;
    limit_conn_zone $binary_remote_addr zone=conn_limit:10m;
    
    # Include site configurations
    include /etc/nginx/conf.d/*.conf;
    include /etc/nginx/sites-enabled/*;
}
EOF

# Test and reload nginx
sudo nginx -t && sudo systemctl reload nginx
```

### 3. System Performance Tuning

```bash
# Apply comprehensive system optimizations
sudo tee /etc/sysctl.d/99-claude-performance.conf > /dev/null << 'EOF'
# Network Performance
net.core.somaxconn = 65535
net.core.netdev_max_backlog = 65535
net.core.rmem_default = 31457280
net.core.rmem_max = 134217728
net.core.wmem_default = 31457280
net.core.wmem_max = 134217728
net.core.optmem_max = 25165824

# TCP Optimization
net.ipv4.tcp_mem = 786432 1048576 26777216
net.ipv4.tcp_rmem = 4096 87380 134217728
net.ipv4.tcp_wmem = 4096 65536 134217728
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.tcp_fin_timeout = 15
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_timestamps = 1
net.ipv4.tcp_sack = 1
net.ipv4.tcp_window_scaling = 1
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_max_tw_buckets = 2000000
net.ipv4.tcp_slow_start_after_idle = 0
net.ipv4.tcp_no_metrics_save = 1
net.ipv4.tcp_moderate_rcvbuf = 1

# Connection tracking
net.netfilter.nf_conntrack_max = 524288
net.netfilter.nf_conntrack_tcp_timeout_established = 86400

# Virtual memory
vm.swappiness = 10
vm.dirty_ratio = 15
vm.dirty_background_ratio = 5
vm.overcommit_memory = 1

# File system
fs.file-max = 2097152
fs.nr_open = 1048576
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
EOF

# Apply settings
sudo sysctl -p /etc/sysctl.d/99-claude-performance.conf

# Enable BBR congestion control
sudo modprobe tcp_bbr
echo "tcp_bbr" | sudo tee -a /etc/modules-load.d/bbr.conf

# Optimize CPU governor
sudo apt install -y cpufrequtils
echo 'GOVERNOR="performance"' | sudo tee /etc/default/cpufrequtils
sudo systemctl restart cpufrequtils

# Disable transparent huge pages
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/enabled
echo 'never' | sudo tee /sys/kernel/mm/transparent_hugepage/defrag

# Add to rc.local for persistence
sudo tee /etc/rc.local > /dev/null << 'EOF'
#!/bin/bash
echo never > /sys/kernel/mm/transparent_hugepage/enabled
echo never > /sys/kernel/mm/transparent_hugepage/defrag
exit 0
EOF
sudo chmod +x /etc/rc.local
```

## Backup & Disaster Recovery

### 1. Automated Backup System

```bash
# Create backup script
sudo tee /usr/local/bin/claude-backup > /dev/null << 'EOF'
#!/bin/bash

# Configuration
BACKUP_ROOT="/home/claude-companion/backups"
REMOTE_BACKUP="s3://your-bucket/claude-companion-backups"  # Optional S3 backup
RETENTION_DAYS=30
DATE=$(date +%Y%m%d_%H%M%S)
BACKUP_DIR="$BACKUP_ROOT/$DATE"

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Function to log messages
log() {
    echo "[$(date "+%Y-%m-%d %H:%M:%S")] $1" | tee -a "$BACKUP_ROOT/backup.log"
}

log "Starting backup process..."

# 1. Backup application code
log "Backing up application code..."
tar -czf "$BACKUP_DIR/app_$DATE.tar.gz" \
    -C /home/claude-companion/app \
    --exclude="node_modules" \
    --exclude=".git" \
    --exclude="logs" \
    .

# 2. Backup configuration
log "Backing up configuration..."
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" \
    /etc/claude-companion/.env.production \
    /home/claude-companion/app/ecosystem.config.js \
    /etc/nginx/sites-available/claude-companion \
    /etc/letsencrypt/live/api.claudecompanion.com/ \
    /etc/systemd/system/pm2-claude-companion.service

# 3. Backup PM2 configuration
log "Backing up PM2 configuration..."
sudo -u claude-companion pm2 save
tar -czf "$BACKUP_DIR/pm2_$DATE.tar.gz" \
    /home/claude-companion/.pm2/dump.pm2

# 4. Backup session data
log "Backing up session data..."
if [ -d "/var/lib/claude-companion/sessions" ]; then
    tar -czf "$BACKUP_DIR/sessions_$DATE.tar.gz" \
        /var/lib/claude-companion/sessions
fi

# 5. Backup connection state
if [ -d "/var/lib/claude-companion/connections" ]; then
    tar -czf "$BACKUP_DIR/connections_$DATE.tar.gz" \
        /var/lib/claude-companion/connections
fi

# 6. Database dump (if using external database)
# mysqldump -u claude -p claude_companion | gzip > "$BACKUP_DIR/database_$DATE.sql.gz"
# pg_dump -U claude claude_companion | gzip > "$BACKUP_DIR/database_$DATE.sql.gz"

# 7. Create backup manifest
cat > "$BACKUP_DIR/manifest.txt" << MANIFEST
Backup Date: $(date)
Server: $(hostname)
IP: $(hostname -I | awk "{print \$1}")
Node Version: $(node -v)
PM2 Version: $(pm2 -v)
App Version: $(cd /home/claude-companion/app && git describe --tags --always 2>/dev/null || echo "unknown")
Backup Contents:
$(ls -la "$BACKUP_DIR")
MANIFEST

# 8. Create consolidated backup
log "Creating consolidated backup archive..."
tar -czf "$BACKUP_ROOT/claude-companion-backup-$DATE.tar.gz" -C "$BACKUP_ROOT" "$DATE"

# 9. Upload to remote storage (optional)
if command -v aws &> /dev/null && [ -n "$REMOTE_BACKUP" ]; then
    log "Uploading to S3..."
    aws s3 cp "$BACKUP_ROOT/claude-companion-backup-$DATE.tar.gz" "$REMOTE_BACKUP/" \
        --storage-class GLACIER_IR
fi

# 10. Cleanup old backups
log "Cleaning up old backups..."
find "$BACKUP_ROOT" -name "claude-companion-backup-*.tar.gz" -mtime +$RETENTION_DAYS -delete
find "$BACKUP_ROOT" -type d -name "[0-9]*_[0-9]*" -mtime +1 -exec rm -rf {} +

# 11. Verify backup
BACKUP_SIZE=$(du -sh "$BACKUP_ROOT/claude-companion-backup-$DATE.tar.gz" | cut -f1)
log "Backup completed successfully. Size: $BACKUP_SIZE"

# 12. Send notification
echo "Claude Companion backup completed at $(date). Size: $BACKUP_SIZE" | \
    mail -s "[Backup] Claude Companion" admin@claudecompanion.com

exit 0
EOF

sudo chmod +x /usr/local/bin/claude-backup
sudo chown claude-companion:claude-companion /usr/local/bin/claude-backup

# Schedule daily backups
(sudo -u claude-companion crontab -l 2>/dev/null; echo "0 2 * * * /usr/local/bin/claude-backup >> /home/claude-companion/backups/backup.log 2>&1") | sudo -u claude-companion crontab -
```

### 2. Disaster Recovery Procedure

```bash
# Create recovery script
sudo tee /usr/local/bin/claude-restore > /dev/null << 'EOF'
#!/bin/bash

# Recovery script for Claude Companion
set -e

if [ "$#" -ne 1 ]; then
    echo "Usage: $0 <backup-file.tar.gz>"
    echo "Example: $0 /home/claude-companion/backups/claude-companion-backup-20250105_020000.tar.gz"
    exit 1
fi

BACKUP_FILE="$1"
RESTORE_DIR="/tmp/claude-restore-$(date +%Y%m%d_%H%M%S)"

if [ ! -f "$BACKUP_FILE" ]; then
    echo "Error: Backup file not found: $BACKUP_FILE"
    exit 1
fi

echo "=== Claude Companion Disaster Recovery ==="
echo "Backup file: $BACKUP_FILE"
echo "Restore directory: $RESTORE_DIR"
echo ""
echo "This will stop the current service and restore from backup."
read -p "Continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
    echo "Recovery cancelled."
    exit 0
fi

# 1. Create restore directory
echo "Creating restore directory..."
mkdir -p "$RESTORE_DIR"

# 2. Extract backup
echo "Extracting backup..."
tar -xzf "$BACKUP_FILE" -C "$RESTORE_DIR"
BACKUP_DATE=$(ls "$RESTORE_DIR" | head -1)
BACKUP_PATH="$RESTORE_DIR/$BACKUP_DATE"

# 3. Stop services
echo "Stopping services..."
sudo -u claude-companion pm2 stop claude-companion || true
sudo systemctl stop nginx

# 4. Backup current state
echo "Backing up current state..."
CURRENT_BACKUP="/home/claude-companion/backups/pre-restore-$(date +%Y%m%d_%H%M%S)"
mkdir -p "$CURRENT_BACKUP"
cp -r /home/claude-companion/app "$CURRENT_BACKUP/" 2>/dev/null || true
cp /etc/claude-companion/.env.production "$CURRENT_BACKUP/" 2>/dev/null || true

# 5. Restore application code
if [ -f "$BACKUP_PATH/app_"*.tar.gz ]; then
    echo "Restoring application code..."
    rm -rf /home/claude-companion/app/*
    tar -xzf "$BACKUP_PATH/app_"*.tar.gz -C /home/claude-companion/app/
    chown -R claude-companion:claude-companion /home/claude-companion/app/
fi

# 6. Restore configuration
if [ -f "$BACKUP_PATH/config_"*.tar.gz ]; then
    echo "Restoring configuration..."
    tar -xzf "$BACKUP_PATH/config_"*.tar.gz -C /
    chmod 600 /etc/claude-companion/.env.production
    chown claude-companion:claude-companion /etc/claude-companion/.env.production
fi

# 7. Restore PM2 configuration
if [ -f "$BACKUP_PATH/pm2_"*.tar.gz ]; then
    echo "Restoring PM2 configuration..."
    tar -xzf "$BACKUP_PATH/pm2_"*.tar.gz -C /
    sudo -u claude-companion pm2 resurrect
fi

# 8. Restore session data
if [ -f "$BACKUP_PATH/sessions_"*.tar.gz ]; then
    echo "Restoring session data..."
    rm -rf /var/lib/claude-companion/sessions/*
    tar -xzf "$BACKUP_PATH/sessions_"*.tar.gz -C /
    chown -R claude-companion:claude-companion /var/lib/claude-companion/sessions/
fi

# 9. Restore connection state
if [ -f "$BACKUP_PATH/connections_"*.tar.gz ]; then
    echo "Restoring connection state..."
    rm -rf /var/lib/claude-companion/connections/*
    tar -xzf "$BACKUP_PATH/connections_"*.tar.gz -C /
    chown -R claude-companion:claude-companion /var/lib/claude-companion/connections/
fi

# 10. Install dependencies
echo "Installing dependencies..."
cd /home/claude-companion/app/server
sudo -u claude-companion npm ci --production

# 11. Start services
echo "Starting services..."
sudo systemctl start nginx
sudo -u claude-companion pm2 start claude-companion

# 12. Verify services
echo "Verifying services..."
sleep 5
if curl -s http://localhost:3001/health > /dev/null; then
    echo "✓ Health check passed"
else
    echo "✗ Health check failed"
    echo "Check logs: sudo -u claude-companion pm2 logs claude-companion"
fi

# 13. Cleanup
echo "Cleaning up temporary files..."
rm -rf "$RESTORE_DIR"

echo ""
echo "=== Recovery Complete ==="
echo "Pre-restore backup saved to: $CURRENT_BACKUP"
echo "Please verify all services are working correctly."
echo ""
echo "Commands to check status:"
echo "  sudo -u claude-companion pm2 status"
echo "  sudo -u claude-companion pm2 logs claude-companion"
echo "  curl http://localhost:3001/health"
echo ""

exit 0
EOF

sudo chmod +x /usr/local/bin/claude-restore

# Create recovery documentation
sudo tee /home/claude-companion/RECOVERY.md > /dev/null << 'EOF'
# Claude Companion Disaster Recovery Guide

## Quick Recovery Steps

1. **Identify the backup to restore**
   ```bash
   ls -la /home/claude-companion/backups/
   ```

2. **Run the recovery script**
   ```bash
   sudo /usr/local/bin/claude-restore /home/claude-companion/backups/claude-companion-backup-YYYYMMDD_HHMMSS.tar.gz
   ```

3. **Monitor recovery progress**
   The script will:
   - Stop all services
   - Backup current state
   - Restore from backup
   - Restart services
   - Verify health

4. **Post-recovery verification**
   ```bash
   # Check services
   sudo -u claude-companion pm2 status
   
   # Check health
   curl http://localhost:3001/health | jq .
   
   # Check logs
   sudo -u claude-companion pm2 logs claude-companion --lines 100
   
   # Test WebSocket
   wscat -H "Authorization: Bearer YOUR_TOKEN" -c ws://localhost:3001/ws
   ```

## Manual Recovery (if script fails)

1. Extract backup manually
2. Stop services
3. Replace files
4. Update permissions
5. Restart services

See detailed steps in deployment documentation.

## Emergency Contacts

- System Admin: admin@claudecompanion.com
- On-call: +1-XXX-XXX-XXXX
- Escalation: manager@claudecompanion.com
EOF
```

## Troubleshooting Guide

### Common Issues and Solutions

#### 1. AICLI Not Found or Not Working

```bash
# Check if AICLI is installed
which claude || which aicli

# Test AICLI directly
claude --version || aicli --version

# Check PATH in PM2 environment
sudo -u claude-companion pm2 env claude-companion | grep PATH

# Update executable path
sudo nano /etc/claude-companion/.env.production
# Set CLAUDE_EXECUTABLE_PATH=/correct/path/to/claude

# Restart service
sudo -u claude-companion pm2 restart claude-companion
```

#### 2. WebSocket Connection Issues

```bash
# Check nginx WebSocket configuration
sudo nginx -T | grep -A10 "location /ws"

# Monitor WebSocket connections
ss -tan | grep :3001 | grep ESTABLISHED | wc -l

# Check for timeout issues in logs
sudo tail -f /var/log/nginx/claude-companion-error.log

# Increase timeouts if needed
sudo nano /etc/nginx/sites-available/claude-companion
# Increase proxy_read_timeout and proxy_send_timeout

# Test WebSocket directly
wscat -H "Authorization: Bearer YOUR_TOKEN" -c ws://localhost:3001/ws
```

#### 3. High Memory Usage

```bash
# Check current memory usage
sudo -u claude-companion pm2 monit

# Analyze memory leak
sudo -u claude-companion pm2 install pm2-memory-profiler
sudo -u claude-companion pm2 profiler:heap:snapshot claude-companion

# Check for zombie AICLI processes
ps aux | grep -E "(claude|aicli)" | grep -v grep

# Kill zombie processes
pkill -f "claude|aicli"

# Adjust memory limits
sudo -u claude-companion pm2 set claude-companion:max_memory_restart 3G
sudo -u claude-companion pm2 restart claude-companion

# Enable garbage collection logs
node --trace-gc /home/claude-companion/app/server/src/index.js
```

#### 4. Push Notification Failures

```bash
# Check APNS certificate validity
openssl x509 -in /etc/claude-companion/certs/apns-cert.pem -noout -dates

# Test APNS connection
openssl s_client -connect api.push.apple.com:443 \
  -cert /etc/claude-companion/certs/apns-cert.pem \
  -key /etc/claude-companion/certs/apns-key.pem

# Check push notification stats
curl -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3001/api/push-notifications/stats | jq .

# Clear bad tokens
curl -X DELETE -H "Authorization: Bearer YOUR_TOKEN" \
  http://localhost:3001/api/push-notifications/tokens/invalid

# Monitor push notification logs
grep -i "push" /var/log/claude-companion/output.log | tail -20
```

#### 5. Session Persistence Issues

```bash
# Check session storage
ls -la /var/lib/claude-companion/sessions/

# Verify permissions
ls -ld /var/lib/claude-companion/sessions/

# Check disk space
df -h /var/lib/claude-companion/

# Monitor session creation/expiry
grep -E "Session (created|expired)" /var/log/claude-companion/output.log | tail -20

# Clear old sessions manually
find /var/lib/claude-companion/sessions -name "*.json" -mtime +7 -delete
```

#### 6. Performance Degradation

```bash
# Check system resources
htop
iotop
nethogs

# Analyze nginx access logs
awk '{print $7}' /var/log/nginx/claude-companion-access.log | sort | uniq -c | sort -rn | head -20

# Check slow queries
awk '{if($10>1000) print $0}' /var/log/nginx/claude-companion-access.log | tail -20

# Monitor Node.js event loop
sudo -u claude-companion pm2 install pm2-event-loop-inspector

# Check for blocking operations
node --trace-sync-io /home/claude-companion/app/server/src/index.js
```

### Advanced Debugging

```bash
# Enable comprehensive debug logging
sudo -u claude-companion bash -c 'DEBUG=* pm2 restart claude-companion'

# Enable specific debug namespaces
sudo -u claude-companion bash -c 'DEBUG=websocket,aicli,session pm2 restart claude-companion'

# Real-time log monitoring with filtering
sudo -u claude-companion pm2 logs claude-companion --lines 1000 | grep -E "(error|warn|fail)"

# Generate diagnostic report
sudo tee /usr/local/bin/claude-diagnostic > /dev/null << 'EOF'
#!/bin/bash

REPORT_FILE="/tmp/claude-diagnostic-$(date +%Y%m%d_%H%M%S).txt"

echo "Claude Companion Diagnostic Report" > "$REPORT_FILE"
echo "Generated: $(date)" >> "$REPORT_FILE"
echo "======================================" >> "$REPORT_FILE"

echo -e "\n## System Information" >> "$REPORT_FILE"
uname -a >> "$REPORT_FILE"
lsb_release -a >> "$REPORT_FILE" 2>&1

echo -e "\n## Resource Usage" >> "$REPORT_FILE"
free -h >> "$REPORT_FILE"
df -h >> "$REPORT_FILE"
top -bn1 | head -20 >> "$REPORT_FILE"

echo -e "\n## Process Status" >> "$REPORT_FILE"
sudo -u claude-companion pm2 list >> "$REPORT_FILE"
sudo -u claude-companion pm2 show claude-companion >> "$REPORT_FILE"

echo -e "\n## Network Status" >> "$REPORT_FILE"
ss -tulpn | grep -E "(3001|443|80)" >> "$REPORT_FILE"
netstat -an | grep -c ESTABLISHED >> "$REPORT_FILE"

echo -e "\n## Recent Errors" >> "$REPORT_FILE"
tail -50 /var/log/claude-companion/error.log >> "$REPORT_FILE" 2>&1
grep -i error /var/log/nginx/claude-companion-error.log | tail -20 >> "$REPORT_FILE" 2>&1

echo -e "\n## Health Check" >> "$REPORT_FILE"
curl -s http://localhost:3001/health >> "$REPORT_FILE"

echo -e "\n## Configuration (sanitized)" >> "$REPORT_FILE"
grep -v "TOKEN\|KEY\|PASSWORD" /etc/claude-companion/.env.production >> "$REPORT_FILE"

echo "\nDiagnostic report saved to: $REPORT_FILE"
cat "$REPORT_FILE"
EOF

sudo chmod +x /usr/local/bin/claude-diagnostic

# Run diagnostic
sudo /usr/local/bin/claude-diagnostic

# Enable Node.js debugging
sudo -u claude-companion pm2 start claude-companion --node-args="--inspect=0.0.0.0:9229"

# Use Chrome DevTools for debugging
# Navigate to chrome://inspect and connect to remote target
```

## Maintenance & Operations

### Maintenance Schedule

#### Daily Tasks

```bash
# Create daily maintenance script
sudo tee /usr/local/bin/claude-daily-maintenance > /dev/null << 'EOF'
#!/bin/bash

LOG_FILE="/var/log/claude-companion/maintenance.log"

log() {
    echo "[$(date)] $1" | tee -a "$LOG_FILE"
}

log "Starting daily maintenance..."

# 1. Check service health
if ! curl -s http://localhost:3001/health > /dev/null; then
    log "WARNING: Health check failed"
    # Send alert
fi

# 2. Check error logs
ERROR_COUNT=$(grep -c ERROR /var/log/claude-companion/error.log 2>/dev/null || echo 0)
if [ "$ERROR_COUNT" -gt 100 ]; then
    log "WARNING: High error count: $ERROR_COUNT"
fi

# 3. Check disk space
DISK_USAGE=$(df -h / | awk 'NR==2 {print $5}' | sed 's/%//')
if [ "$DISK_USAGE" -gt 80 ]; then
    log "WARNING: Disk usage high: ${DISK_USAGE}%"
fi

# 4. Clean temporary files
find /tmp -name "claude-*" -mtime +1 -delete

# 5. Verify backups
LATEST_BACKUP=$(ls -t /home/claude-companion/backups/*.tar.gz 2>/dev/null | head -1)
if [ -z "$LATEST_BACKUP" ]; then
    log "WARNING: No recent backups found"
fi

log "Daily maintenance completed"
EOF

sudo chmod +x /usr/local/bin/claude-daily-maintenance
sudo ln -s /usr/local/bin/claude-daily-maintenance /etc/cron.daily/
```

#### Weekly Tasks

```bash
# Create weekly maintenance script
sudo tee /usr/local/bin/claude-weekly-maintenance > /dev/null << 'EOF'
#!/bin/bash

# 1. Security updates
apt update
apt list --upgradable | grep -i security

# 2. Clean old logs
journalctl --vacuum-time=7d

# 3. Analyze performance
/usr/local/bin/claude-logs

# 4. Check SSL certificate expiry
openssl x509 -in /etc/letsencrypt/live/api.claudecompanion.com/cert.pem -noout -dates

# 5. Test monitoring alerts
/usr/local/bin/claude-health-check

echo "Weekly maintenance completed"
EOF

sudo chmod +x /usr/local/bin/claude-weekly-maintenance
```

#### Monthly Tasks

```bash
# Create monthly maintenance script
sudo tee /usr/local/bin/claude-monthly-maintenance > /dev/null << 'EOF'
#!/bin/bash

# 1. Update dependencies
cd /home/claude-companion/app/server
sudo -u claude-companion npm outdated
sudo -u claude-companion npm audit

# 2. Test backup restoration
TEST_BACKUP=$(ls -t /home/claude-companion/backups/*.tar.gz | head -1)
if [ -n "$TEST_BACKUP" ]; then
    echo "Testing backup restoration with: $TEST_BACKUP"
    # Run in test environment
fi

# 3. Review and optimize database/storage
du -sh /var/lib/claude-companion/*
find /var/lib/claude-companion -name "*.json" -mtime +30 | wc -l

# 4. Security audit
lynis audit system

# 5. Performance analysis
pm2 report

echo "Monthly maintenance completed"
EOF

sudo chmod +x /usr/local/bin/claude-monthly-maintenance
```

### Zero-Downtime Update Procedure

```bash
# Create update script
sudo tee /usr/local/bin/claude-update > /dev/null << 'EOF'
#!/bin/bash

set -e

# Configuration
APP_DIR="/home/claude-companion/app"
BACKUP_SCRIPT="/usr/local/bin/claude-backup"
HEALTH_URL="https://api.claudecompanion.com/health"

log() {
    echo "[$(date)] $1"
}

log "Starting Claude Companion update process..."

# 1. Pre-update checks
log "Running pre-update checks..."
if ! curl -s "$HEALTH_URL" > /dev/null; then
    log "ERROR: Health check failed before update"
    exit 1
fi

# 2. Create backup
log "Creating backup..."
"$BACKUP_SCRIPT"

# 3. Fetch latest code
log "Fetching latest code..."
cd "$APP_DIR"
sudo -u claude-companion git fetch origin
LATEST_COMMIT=$(sudo -u claude-companion git rev-parse origin/main)
CURRENT_COMMIT=$(sudo -u claude-companion git rev-parse HEAD)

if [ "$LATEST_COMMIT" = "$CURRENT_COMMIT" ]; then
    log "Already up to date"
    exit 0
fi

# 4. Show changes
log "Changes to be applied:"
sudo -u claude-companion git log --oneline HEAD..origin/main

# 5. Confirm update
read -p "Continue with update? (yes/no): " CONFIRM
if [ "$CONFIRM" != "yes" ]; then
    log "Update cancelled"
    exit 0
fi

# 6. Pull changes
log "Pulling changes..."
sudo -u claude-companion git pull origin main

# 7. Install dependencies
log "Installing dependencies..."
cd "$APP_DIR/server"
sudo -u claude-companion npm ci --production

# 8. Run migrations if exists
if [ -f "$APP_DIR/server/migrations/migrate.js" ]; then
    log "Running migrations..."
    sudo -u claude-companion npm run migrate
fi

# 9. Graceful reload
log "Performing graceful reload..."
sudo -u claude-companion pm2 reload claude-companion

# 10. Wait for service to be ready
log "Waiting for service to be ready..."
sleep 10

# 11. Verify deployment
log "Verifying deployment..."
if curl -s "$HEALTH_URL" > /dev/null; then
    log "✓ Update completed successfully"
    NEW_VERSION=$(sudo -u claude-companion git describe --tags --always)
    log "New version: $NEW_VERSION"
else
    log "✗ Health check failed after update"
    log "Rolling back..."
    sudo -u claude-companion git reset --hard "$CURRENT_COMMIT"
    sudo -u claude-companion npm ci --production
    sudo -u claude-companion pm2 reload claude-companion
    exit 1
fi

# 12. Clean up
log "Cleaning up..."
sudo -u claude-companion npm prune --production
sudo -u claude-companion pm2 flush

log "Update process completed"
EOF

sudo chmod +x /usr/local/bin/claude-update

# Run update
sudo /usr/local/bin/claude-update
```

## Production Deployment Checklist

### Pre-Deployment
- [ ] System requirements verified
- [ ] Domain name configured
- [ ] DNS records set up
- [ ] Server provisioned
- [ ] SSH access configured
- [ ] Root access available

### Security
- [ ] Dedicated user created
- [ ] SSH key authentication enabled
- [ ] Password authentication disabled
- [ ] Firewall configured (UFW)
- [ ] Fail2ban installed and configured
- [ ] SSL certificates obtained
- [ ] Security headers configured
- [ ] Authentication tokens generated
- [ ] File permissions hardened
- [ ] SELinux/AppArmor configured
- [ ] Automatic security updates enabled

### Application
- [ ] Node.js installed
- [ ] Application code deployed
- [ ] Dependencies installed
- [ ] Environment variables configured
- [ ] PM2 process manager configured
- [ ] Startup scripts created
- [ ] Log rotation configured
- [ ] Session persistence verified

### Infrastructure
- [ ] nginx reverse proxy configured
- [ ] WebSocket support enabled
- [ ] Rate limiting configured
- [ ] Compression enabled
- [ ] Caching headers set
- [ ] CORS properly configured
- [ ] Health check endpoint accessible

### Monitoring
- [ ] PM2 monitoring enabled
- [ ] System monitoring tools installed
- [ ] Log aggregation configured
- [ ] Health checks scheduled
- [ ] Alert notifications configured
- [ ] Performance baselines established
- [ ] Resource limits set
- [ ] Metrics endpoint protected

### Backup & Recovery
- [ ] Backup script created
- [ ] Backup schedule configured
- [ ] Remote backup storage set up
- [ ] Recovery script tested
- [ ] Recovery documentation written
- [ ] Restore procedure verified
- [ ] Backup retention policy set

### Performance
- [ ] System limits optimized
- [ ] nginx tuned
- [ ] Node.js optimized
- [ ] Kernel parameters tuned
- [ ] CPU governor set
- [ ] Memory management configured
- [ ] Network stack optimized

### Operations
- [ ] Maintenance scripts created
- [ ] Update procedure documented
- [ ] Monitoring dashboards set up
- [ ] On-call procedures defined
- [ ] Escalation paths documented
- [ ] Runbooks created
- [ ] Team trained

### Testing
- [ ] Health endpoint responsive
- [ ] WebSocket connections work
- [ ] Authentication verified
- [ ] API endpoints tested
- [ ] Push notifications working
- [ ] Load testing completed
- [ ] Failover tested
- [ ] Backup restoration tested

### Documentation
- [ ] Deployment guide updated
- [ ] API documentation current
- [ ] Troubleshooting guide complete
- [ ] Architecture documented
- [ ] Security policies documented
- [ ] SLAs defined
- [ ] Change log maintained

## Production Support

### Support Tiers

#### Tier 1 - Automated Monitoring
- Health check failures
- High error rates
- Resource exhaustion
- Certificate expiration

#### Tier 2 - Operations Team
- Service restarts
- Configuration changes
- Backup restoration
- Performance tuning

#### Tier 3 - Development Team
- Code-level debugging
- Feature issues
- Complex troubleshooting
- Architecture changes

### Incident Response

1. **Detection**
   - Automated alerts
   - User reports
   - Monitoring dashboards

2. **Triage**
   - Severity assessment
   - Impact analysis
   - Resource assignment

3. **Resolution**
   - Follow runbooks
   - Apply fixes
   - Test thoroughly
   - Document actions

4. **Post-Mortem**
   - Root cause analysis
   - Prevention measures
   - Process improvements

### Contact Information

**Email Support**: support@claudecompanion.com

**Emergency Hotline**: +1-XXX-XXX-XXXX (24/7)

**Slack Channel**: #claude-companion-ops

**Status Page**: https://status.claudecompanion.com

### Useful Commands

```bash
# Quick health check
claude-health-check

# View current status
claude-monitor

# Check logs
sudo -u claude-companion pm2 logs claude-companion --lines 100

# Run diagnostics
claude-diagnostic

# Create support bundle
tar -czf support-bundle-$(date +%Y%m%d).tar.gz \
  /var/log/claude-companion/ \
  /tmp/claude-diagnostic-*.txt \
  /home/claude-companion/app/ecosystem.config.js
```

## Additional Resources

- [Architecture Documentation](./ARCHITECTURE.md)
- [API Reference](./API.md)
- [Troubleshooting Guide](./TROUBLESHOOTING.md)
- [Security Best Practices](./SECURITY.md)
- [GitHub Repository](https://github.com/your-username/claude-companion)

---

*Last updated: January 2025*