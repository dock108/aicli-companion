# ngrok Setup Guide for Claude Companion

## Overview
ngrok provides secure tunnels to expose your local Claude Companion server to the internet, allowing you to connect from anywhere. This guide walks through the complete setup process.

## Why Use ngrok?

- **Remote Access**: Connect to your Claude Companion server from anywhere
- **Secure**: All traffic is encrypted through ngrok's tunnels
- **No Port Forwarding**: No need to configure your router or firewall
- **Dynamic URLs**: Works even if your IP address changes

## Prerequisites

- Claude Companion macOS app installed and running
- Internet connection
- Free ngrok account (instructions below)

## Setup Instructions

### Method 1: Using the Built-in Setup Wizard (Recommended)

1. **Open Settings**
   - Click the Claude Companion menu bar icon
   - Select "Settings..."
   - Navigate to the "Security" tab

2. **Enable Internet Access**
   - Toggle "Enable Internet Access" ON
   - This automatically enables authentication for security

3. **Launch Setup Wizard**
   - Click "Setup ngrok" button
   - Follow the 3-step wizard:
     - **Step 1**: Sign up for free ngrok account
     - **Step 2**: Copy your auth token from dashboard
     - **Step 3**: Paste token and finish setup

4. **Restart Server**
   - A "Server Restart Required" banner will appear
   - Click "Restart Now" to apply changes

### Method 2: Manual Setup

1. **Sign Up for ngrok**
   - Visit [ngrok.com/signup](https://ngrok.com/signup)
   - Create a free account
   - Verify your email

2. **Get Your Auth Token**
   - Log into [dashboard.ngrok.com](https://dashboard.ngrok.com)
   - Navigate to "Your Authtoken" section
   - Copy the auth token (looks like: `2abc...xyz`)

3. **Configure in Claude Companion**
   - Open Settings → Security tab
   - Enable "Enable Internet Access"
   - Select "ngrok" as provider
   - Paste your auth token
   - Click "Restart Now" when prompted

## Using Your Tunnel

Once configured and server restarted:

1. **Check Connection Status**
   - Menu bar dropdown shows "Public: Active 🌐"
   - Public URL appears in Security settings

2. **Share Your Server**
   - Copy public URL from menu bar (automatic when tunneling)
   - Share URL with your devices/collaborators
   - Include auth token when sharing (found in Security tab)

3. **Connect from iOS App**
   - Open Claude Companion iOS app
   - Scan QR code from macOS menu bar
   - Or manually enter public URL and auth token

## Best Practices

### Security

1. **Always Use Authentication**
   - Authentication is automatically enforced when tunneling
   - Never disable auth when exposing to internet
   - Regularly rotate auth tokens

2. **Token Management**
   - Keep your ngrok auth token secure
   - Don't commit tokens to version control
   - Use different tokens for different environments

3. **Monitor Access**
   - Check active sessions in menu bar
   - Review ngrok dashboard for connection logs
   - Disconnect suspicious sessions immediately

### Performance

1. **Bandwidth Limits**
   - Free ngrok accounts have bandwidth limits
   - Monitor usage in ngrok dashboard
   - Upgrade if you need more bandwidth

2. **Connection Stability**
   - ngrok URLs change on restart (free tier)
   - Consider ngrok paid plans for static URLs
   - Use authentication tokens for consistent access

## Troubleshooting

### Common Issues

**"ngrok auth token required"**
- You haven't configured your auth token
- Solution: Follow setup wizard or manual setup steps

**"Server Restart Required" appears**
- Settings changed that need server restart
- Solution: Click "Restart Now" button

**Public URL not appearing**
- Server may not have restarted properly
- Solution: Stop and start server manually

**Connection refused from remote**
- Authentication may be misconfigured
- Solution: Verify auth token is correct in both server and client

### Advanced Configuration

**Custom Domains** (Paid ngrok feature)
```bash
# Set custom domain in environment
NGROK_DOMAIN=your-domain.ngrok.io
```

**Region Selection**
```bash
# Use specific ngrok region
NGROK_REGION=eu  # Europe
NGROK_REGION=ap  # Asia/Pacific
NGROK_REGION=au  # Australia
NGROK_REGION=sa  # South America
NGROK_REGION=jp  # Japan
NGROK_REGION=in  # India
```

## Alternative Tunneling Services

While ngrok is recommended and integrated, alternatives include:

- **Cloudflare Tunnel** (planned support)
- **Tailscale** (VPN-based approach)
- **localtunnel** (open source alternative)
- **bore** (minimal tunneling solution)

## Pricing

### ngrok Free Tier
- 1 online ngrok process
- 4 tunnels per ngrok process
- 40 connections per minute
- Random URL (changes on restart)

### ngrok Paid Plans
- Static URLs
- Custom domains
- Higher rate limits
- IP whitelisting
- OAuth/SAML support

## Support

- **ngrok Documentation**: [ngrok.com/docs](https://ngrok.com/docs)
- **ngrok Status**: [status.ngrok.com](https://status.ngrok.com)
- **Claude Companion Issues**: [GitHub Issues](https://github.com/anthropics/claude-companion/issues)

## Security Notice

⚠️ **Important**: When exposing your server to the internet:
- Always use authentication (enforced automatically)
- Regularly update Claude Companion
- Monitor access logs
- Use strong, unique auth tokens
- Consider IP whitelisting for production use