# Deployment Guide

This guide covers deploying Claude Companion Server to production environments.

## Deployment Options

### 1. Standalone Server
- Direct Node.js deployment
- Suitable for personal use
- Simple setup and maintenance

### 2. Containerized (Docker)
- Isolated environment
- Easy scaling
- Consistent deployments

### 3. Cloud Platforms
- AWS EC2/ECS
- Google Cloud Run
- Azure App Service
- DigitalOcean Apps

## Pre-Deployment Checklist

- [ ] Production auth tokens generated
- [ ] TLS certificates obtained
- [ ] Environment variables configured
- [ ] Claude CLI installed and tested
- [ ] Firewall rules configured
- [ ] Monitoring setup completed
- [ ] Backup strategy defined

## Standalone Deployment

### 1. System Requirements

**Minimum**:
- CPU: 2 cores
- RAM: 2 GB
- Storage: 10 GB
- Network: 100 Mbps

**Recommended**:
- CPU: 4 cores
- RAM: 4 GB
- Storage: 20 GB SSD
- Network: 1 Gbps

### 2. Server Setup (Ubuntu/Debian)

```bash
# Update system
sudo apt update && sudo apt upgrade -y

# Install Node.js 18
curl -fsSL https://deb.nodesource.com/setup_18.x | sudo -E bash -
sudo apt install -y nodejs

# Install global dependencies
sudo npm install -g pm2 @anthropic/claude-code

# Create app user
sudo useradd -m -s /bin/bash claude-companion
sudo su - claude-companion
```

### 3. Application Deployment

```bash
# Clone repository
git clone https://github.com/your-repo/claude-companion.git
cd claude-companion/server

# Install dependencies
npm ci --production

# Create production config
cat > .env.production << EOF
NODE_ENV=production
PORT=3001
HOST=0.0.0.0
AUTH_TOKEN=$(openssl rand -hex 32)
ENABLE_BONJOUR=false
CLAUDE_PERMISSION_MODE=default
EOF

# Start with PM2
pm2 start ecosystem.config.js --env production
pm2 save
pm2 startup
```

### 4. PM2 Configuration

**ecosystem.config.js**:
```javascript
module.exports = {
  apps: [{
    name: 'claude-companion',
    script: './src/index.js',
    instances: 1,
    autorestart: true,
    watch: false,
    max_memory_restart: '1G',
    env_production: {
      NODE_ENV: 'production'
    },
    error_file: 'logs/error.log',
    out_file: 'logs/out.log',
    log_file: 'logs/combined.log',
    time: true
  }]
};
```

## Docker Deployment

### 1. Dockerfile

```dockerfile
FROM node:18-alpine

# Install Claude CLI
RUN npm install -g @anthropic/claude-code

# Create app directory
WORKDIR /app

# Copy package files
COPY package*.json ./

# Install production dependencies
RUN npm ci --production

# Copy app source
COPY . .

# Create non-root user
RUN addgroup -g 1001 -S nodejs
RUN adduser -S nodejs -u 1001
USER nodejs

# Expose port
EXPOSE 3001

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=40s \
  CMD node healthcheck.js

# Start server
CMD ["node", "src/index.js"]
```

### 2. Docker Compose

**docker-compose.yml**:
```yaml
version: '3.8'

services:
  claude-companion:
    build: ./server
    container_name: claude-companion-server
    restart: unless-stopped
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=production
      - AUTH_TOKEN=${AUTH_TOKEN}
      - CLAUDE_PERMISSION_MODE=default
    volumes:
      - ./data:/app/data
      - ./logs:/app/logs
      - ./certs:/app/certs:ro
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:3001/health"]
      interval: 30s
      timeout: 10s
      retries: 3
```

### 3. Building and Running

```bash
# Build image
docker build -t claude-companion:latest ./server

# Run with docker-compose
docker-compose up -d

# View logs
docker-compose logs -f

# Update deployment
docker-compose pull
docker-compose up -d
```

## Cloud Deployment

### AWS EC2

1. **Launch Instance**:
   - Amazon Linux 2 or Ubuntu 20.04
   - t3.medium or larger
   - Security group: Allow 22, 80, 443, 3001

2. **Install Dependencies**:
```bash
# Install Node.js
curl -sL https://rpm.nodesource.com/setup_18.x | sudo bash -
sudo yum install nodejs -y

# Install Claude CLI
sudo npm install -g @anthropic/claude-code pm2
```

3. **Deploy Application**:
```bash
# Clone and setup
git clone https://github.com/your-repo/claude-companion.git
cd claude-companion/server
npm ci --production

# Configure systemd
sudo cp deployment/claude-companion.service /etc/systemd/system/
sudo systemctl enable claude-companion
sudo systemctl start claude-companion
```

### Google Cloud Run

1. **Prepare Container**:
```bash
# Build and push to GCR
gcloud builds submit --tag gcr.io/PROJECT-ID/claude-companion

# Deploy to Cloud Run
gcloud run deploy claude-companion \
  --image gcr.io/PROJECT-ID/claude-companion \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars="NODE_ENV=production,AUTH_TOKEN=$AUTH_TOKEN"
```

### Heroku

1. **Create App**:
```bash
heroku create claude-companion-prod
heroku config:set NODE_ENV=production
heroku config:set AUTH_TOKEN=$(openssl rand -hex 32)
```

2. **Deploy**:
```bash
git push heroku main
heroku ps:scale web=1
heroku logs --tail
```

## TLS/SSL Configuration

### 1. Let's Encrypt (Certbot)

```bash
# Install Certbot
sudo apt install certbot python3-certbot-nginx

# Obtain certificate
sudo certbot certonly --standalone -d your-domain.com

# Auto-renewal
sudo certbot renew --dry-run
```

### 2. Nginx Reverse Proxy

**/etc/nginx/sites-available/claude-companion**:
```nginx
server {
    listen 80;
    server_name your-domain.com;
    return 301 https://$server_name$request_uri;
}

server {
    listen 443 ssl http2;
    server_name your-domain.com;

    ssl_certificate /etc/letsencrypt/live/your-domain.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/your-domain.com/privkey.pem;
    
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_ciphers HIGH:!aNULL:!MD5;
    
    location / {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto $scheme;
    }
    
    location /ws {
        proxy_pass http://localhost:3001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 86400;
    }
}
```

## Environment Configuration

### Production .env

```env
# Server Configuration
NODE_ENV=production
PORT=3001
HOST=0.0.0.0

# Security
AUTH_TOKEN=<generate-secure-token>
CORS_ORIGINS=https://your-app.com

# Claude CLI
CLAUDE_CLI_PATH=/usr/local/bin/claude
CLAUDE_TIMEOUT=300000
CLAUDE_PERMISSION_MODE=default
CLAUDE_ALLOWED_TOOLS=Read,Write,Edit

# Features
ENABLE_BONJOUR=false
MAX_SESSIONS=10
SESSION_TIMEOUT=3600000

# Monitoring
ENABLE_METRICS=true
METRICS_PORT=9090

# Logging
LOG_LEVEL=info
LOG_FORMAT=json
```

## Performance Tuning

### 1. Node.js Optimization

```bash
# Increase memory limit
NODE_OPTIONS="--max-old-space-size=2048" node src/index.js

# Enable clustering
pm2 start ecosystem.config.js -i max
```

### 2. System Limits

**/etc/security/limits.conf**:
```
claude-companion soft nofile 65536
claude-companion hard nofile 65536
claude-companion soft nproc 4096
claude-companion hard nproc 4096
```

### 3. Kernel Parameters

**/etc/sysctl.conf**:
```
net.core.somaxconn = 65535
net.ipv4.tcp_max_syn_backlog = 65535
net.ipv4.ip_local_port_range = 1024 65535
net.ipv4.tcp_tw_reuse = 1
```

## Monitoring Setup

### 1. Health Checks

```javascript
// healthcheck.js
const http = require('http');

http.get('http://localhost:3001/health', (res) => {
  process.exit(res.statusCode === 200 ? 0 : 1);
}).on('error', () => {
  process.exit(1);
});
```

### 2. Prometheus Metrics

```javascript
// Add to server
const prometheus = require('prom-client');
const register = new prometheus.Registry();

// Metrics endpoint
app.get('/metrics', (req, res) => {
  res.set('Content-Type', register.contentType);
  res.end(register.metrics());
});
```

### 3. Logging

Configure structured logging for production:
```javascript
const winston = require('winston');

const logger = winston.createLogger({
  level: 'info',
  format: winston.format.json(),
  transports: [
    new winston.transports.File({ filename: 'error.log', level: 'error' }),
    new winston.transports.File({ filename: 'combined.log' })
  ]
});
```

## Backup Strategy

### 1. Configuration Backup

```bash
# Backup script
#!/bin/bash
BACKUP_DIR="/backup/claude-companion"
DATE=$(date +%Y%m%d_%H%M%S)

mkdir -p $BACKUP_DIR
tar -czf $BACKUP_DIR/config_$DATE.tar.gz \
  .env \
  ecosystem.config.js \
  certs/

# Keep last 30 days
find $BACKUP_DIR -name "config_*.tar.gz" -mtime +30 -delete
```

### 2. Automated Backups

```bash
# Add to crontab
0 2 * * * /home/claude-companion/backup.sh
```

## Disaster Recovery

### 1. Recovery Plan
1. Restore server from snapshot/backup
2. Reinstall dependencies
3. Restore configuration files
4. Restart services
5. Verify functionality

### 2. High Availability (Future)
- Load balancer configuration
- Multiple server instances
- Session state in Redis
- Shared file storage

## Security Hardening

### 1. Firewall Rules

```bash
# UFW configuration
sudo ufw default deny incoming
sudo ufw default allow outgoing
sudo ufw allow 22/tcp
sudo ufw allow 80/tcp
sudo ufw allow 443/tcp
sudo ufw allow 3001/tcp
sudo ufw enable
```

### 2. Fail2ban

```ini
# /etc/fail2ban/jail.local
[claude-companion]
enabled = true
port = 3001
filter = claude-companion
logpath = /var/log/claude-companion/access.log
maxretry = 5
bantime = 3600
```

## Post-Deployment

### 1. Verification
- [ ] Server responds to health checks
- [ ] WebSocket connections work
- [ ] Authentication is enforced
- [ ] TLS certificates are valid
- [ ] Monitoring is active
- [ ] Logs are being collected

### 2. Performance Testing

```bash
# Load test with Apache Bench
ab -n 1000 -c 10 https://your-domain.com/health

# WebSocket test
wscat -c wss://your-domain.com/ws?token=YOUR_TOKEN
```

## Maintenance

### Regular Tasks
- Monitor logs daily
- Update dependencies monthly
- Rotate logs weekly
- Review metrics
- Test backups

### Update Process
1. Test updates in staging
2. Backup production
3. Deploy during low usage
4. Monitor for issues
5. Rollback if needed

---

**Last Updated**: 2025-07-27