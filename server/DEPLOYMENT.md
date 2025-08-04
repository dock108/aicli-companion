# Claude Companion Server - Production Deployment Guide

## Overview

This guide covers deploying Claude Companion Server in a production environment, including configuration, security, monitoring, and best practices.

## Prerequisites

- Node.js 18+ installed
- Claude CLI configured and accessible
- SSL certificates for HTTPS (production)
- Process manager (PM2 recommended)
- Reverse proxy (nginx/Apache)
- APNs certificates for push notifications (iOS)

## Environment Configuration

### Required Environment Variables

```bash
# Authentication
AUTH_TOKEN=your-secure-auth-token-here

# Server Configuration
PORT=3001
NODE_ENV=production

# Claude Configuration
CLAUDE_EXECUTABLE_PATH=/usr/local/bin/claude

# Push Notifications (iOS)
APNS_CERT_PATH=/path/to/apns-cert.pem
APNS_KEY_PATH=/path/to/apns-key.pem
APNS_PASSPHRASE=your-passphrase
APNS_BUNDLE_ID=com.yourcompany.claudecompanion

# Session Management
SESSION_TIMEOUT=86400000  # 24 hours in ms
MAX_SESSIONS_PER_CLIENT=5
SESSION_CLEANUP_INTERVAL=3600000  # 1 hour

# WebSocket Configuration
WS_HEARTBEAT_INTERVAL=30000  # 30 seconds
WS_CONNECTION_TIMEOUT=60000  # 1 minute
MAX_WEBSOCKET_CONNECTIONS=1000

# Message Queue
MESSAGE_QUEUE_MAX_SIZE=1000
MESSAGE_RETENTION_PERIOD=3600000  # 1 hour

# Telemetry
TELEMETRY_ENABLED=true
TELEMETRY_RETENTION_PERIOD=604800000  # 7 days

# Connection State
CONNECTION_STATE_STORAGE=memory  # Options: memory, redis, file
CONNECTION_STATE_TTL=86400000  # 24 hours
```

### Create .env File

```bash
# Create production environment file
cp .env.example .env.production
chmod 600 .env.production

# Edit with your production values
nano .env.production
```

## Installation

### 1. Clone and Install Dependencies

```bash
# Clone repository
git clone https://github.com/yourcompany/claude-companion-server.git
cd claude-companion-server

# Install production dependencies only
npm ci --production

# Build if using TypeScript
npm run build
```

### 2. Set Up Process Manager (PM2)

```bash
# Install PM2 globally
npm install -g pm2

# Create ecosystem file
cat > ecosystem.config.js << 'EOF'
module.exports = {
  apps: [{
    name: 'claude-companion-server',
    script: './server/src/index.js',
    instances: 1,  // Single instance due to Claude CLI
    exec_mode: 'fork',
    env: {
      NODE_ENV: 'production',
      PORT: 3001
    },
    env_production: {
      NODE_ENV: 'production',
      PORT: 3001
    },
    error_file: './logs/err.log',
    out_file: './logs/out.log',
    log_file: './logs/combined.log',
    time: true,
    max_memory_restart: '1G',
    node_args: '--max-old-space-size=1024',
    watch: false,
    ignore_watch: ['node_modules', 'logs', '.git'],
    max_restarts: 10,
    min_uptime: '10s',
    restart_delay: 4000,
    autorestart: true
  }]
};
EOF

# Start with PM2
pm2 start ecosystem.config.js --env production

# Save PM2 configuration
pm2 save

# Set up PM2 startup script
pm2 startup
```

### 3. Configure Reverse Proxy (nginx)

```nginx
# /etc/nginx/sites-available/claude-companion
server {
    listen 80;
    server_name api.claudecompanion.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name api.claudecompanion.com;

    # SSL Configuration
    ssl_certificate /etc/letsencrypt/live/api.claudecompanion.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/api.claudecompanion.com/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    ssl_prefer_server_ciphers on;

    # Security headers
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-XSS-Protection "1; mode=block" always;
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;

    # WebSocket support
    location /ws {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # WebSocket timeouts
        proxy_read_timeout 86400;
        proxy_send_timeout 86400;
        
        # Disable buffering for WebSocket
        proxy_buffering off;
    }

    # REST API
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
        
        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;
        
        # Body size for file uploads
        client_max_body_size 10M;
    }

    # Health check endpoint
    location /health {
        proxy_pass http://localhost:3001/health;
        access_log off;
    }
}
```

### 4. Set Up SSL Certificates

```bash
# Install Certbot
sudo apt-get update
sudo apt-get install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot --nginx -d api.claudecompanion.com

# Auto-renewal
sudo certbot renew --dry-run
```

## Security Configuration

### 1. Firewall Rules

```bash
# Allow only necessary ports
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow ssh
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw enable
```

### 2. Authentication Token

```bash
# Generate secure token
openssl rand -base64 32

# Set in environment
export AUTH_TOKEN="your-generated-token"
```

### 3. File Permissions

```bash
# Secure directories
chmod 750 /path/to/claude-companion-server
chmod 600 .env.production
chmod 700 logs/

# Create dedicated user
sudo useradd -r -s /bin/false claude-companion
sudo chown -R claude-companion:claude-companion /path/to/claude-companion-server
```

## Monitoring

### 1. Application Monitoring

```bash
# PM2 monitoring
pm2 monit

# View logs
pm2 logs claude-companion-server

# View metrics
pm2 info claude-companion-server
```

### 2. System Monitoring

```bash
# Install monitoring tools
sudo apt-get install htop iotop nethogs

# Monitor resources
htop  # CPU and memory
iotop  # Disk I/O
nethogs  # Network usage
```

### 3. Log Management

```bash
# Set up log rotation
cat > /etc/logrotate.d/claude-companion << 'EOF'
/path/to/claude-companion-server/logs/*.log {
    daily
    rotate 14
    compress
    delaycompress
    missingok
    notifempty
    create 0640 claude-companion claude-companion
    sharedscripts
    postrotate
        pm2 reloadLogs
    endscript
}
EOF
```

### 4. Health Checks

```bash
# Set up health check monitoring
curl -f https://api.claudecompanion.com/health || alert-admin

# Add to cron for regular checks
*/5 * * * * curl -f https://api.claudecompanion.com/health || /usr/local/bin/alert-admin
```

## Performance Tuning

### 1. Node.js Optimization

```bash
# Set Node.js flags in PM2 config
node_args: [
  '--max-old-space-size=2048',
  '--optimize-for-size',
  '--max-semi-space-size=128',
  '--max-heap-size=2048'
]
```

### 2. nginx Optimization

```nginx
# Add to nginx.conf
worker_processes auto;
worker_rlimit_nofile 65535;

events {
    worker_connections 4096;
    use epoll;
    multi_accept on;
}

http {
    # Connection settings
    keepalive_timeout 65;
    keepalive_requests 100;
    
    # Buffer settings
    client_body_buffer_size 16K;
    client_header_buffer_size 1k;
    large_client_header_buffers 4 16k;
    
    # Compression
    gzip on;
    gzip_vary on;
    gzip_proxied any;
    gzip_comp_level 6;
    gzip_types text/plain text/css text/xml text/javascript application/json application/javascript application/xml+rss application/rss+xml application/atom+xml image/svg+xml;
}
```

### 3. System Limits

```bash
# Edit /etc/security/limits.conf
claude-companion soft nofile 65535
claude-companion hard nofile 65535
claude-companion soft nproc 32768
claude-companion hard nproc 32768

# Edit /etc/sysctl.conf
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
```

## Backup and Recovery

### 1. Backup Strategy

```bash
#!/bin/bash
# backup.sh
BACKUP_DIR="/backup/claude-companion"
DATE=$(date +%Y%m%d_%H%M%S)

# Create backup directory
mkdir -p "$BACKUP_DIR"

# Backup configuration
tar -czf "$BACKUP_DIR/config_$DATE.tar.gz" \
  .env.production \
  ecosystem.config.js \
  /etc/nginx/sites-available/claude-companion

# Backup logs (optional)
tar -czf "$BACKUP_DIR/logs_$DATE.tar.gz" logs/

# Backup session data (if using file storage)
if [ -d "sessions" ]; then
  tar -czf "$BACKUP_DIR/sessions_$DATE.tar.gz" sessions/
fi

# Clean old backups (keep 30 days)
find "$BACKUP_DIR" -name "*.tar.gz" -mtime +30 -delete
```

### 2. Recovery Procedure

```bash
# Stop services
pm2 stop claude-companion-server

# Restore configuration
tar -xzf /backup/claude-companion/config_LATEST.tar.gz

# Restore session data if needed
tar -xzf /backup/claude-companion/sessions_LATEST.tar.gz

# Restart services
pm2 start claude-companion-server
```

## Troubleshooting

### Common Issues

1. **Claude CLI not found**
   ```bash
   # Verify PATH
   which claude
   # Update CLAUDE_EXECUTABLE_PATH in .env
   ```

2. **WebSocket connection drops**
   ```bash
   # Check nginx timeout settings
   # Increase proxy_read_timeout and proxy_send_timeout
   ```

3. **High memory usage**
   ```bash
   # Check for memory leaks
   pm2 describe claude-companion-server
   # Adjust --max-old-space-size if needed
   ```

4. **Push notifications not working**
   ```bash
   # Verify APNS certificates
   openssl x509 -in /path/to/cert.pem -text -noout
   # Check expiration date
   ```

### Debug Mode

```bash
# Enable debug logging
DEBUG=* pm2 restart claude-companion-server

# View debug logs
pm2 logs claude-companion-server --lines 1000
```

## Maintenance

### Regular Tasks

1. **Daily**
   - Monitor error logs
   - Check health endpoint
   - Review telemetry metrics

2. **Weekly**
   - Review and rotate logs
   - Check disk space
   - Update security patches

3. **Monthly**
   - Review performance metrics
   - Update dependencies
   - Test backup restoration
   - Renew SSL certificates (if needed)

### Update Procedure

```bash
# 1. Backup current deployment
./backup.sh

# 2. Pull latest changes
git pull origin main

# 3. Install/update dependencies
npm ci --production

# 4. Run migrations if any
npm run migrate

# 5. Restart with zero downtime
pm2 reload claude-companion-server

# 6. Verify deployment
curl https://api.claudecompanion.com/health
```

## Production Checklist

- [ ] Environment variables configured
- [ ] SSL certificates installed
- [ ] Firewall rules configured
- [ ] Process manager set up
- [ ] Reverse proxy configured
- [ ] Logging configured
- [ ] Monitoring set up
- [ ] Backup strategy implemented
- [ ] Health checks active
- [ ] Authentication tokens secured
- [ ] File permissions set correctly
- [ ] System limits optimized
- [ ] Error alerting configured

## Support

For production support issues:
1. Check logs: `pm2 logs claude-companion-server`
2. Review metrics: `GET /api/telemetry`
3. Test health: `GET /health`
4. Contact support with logs and metrics data