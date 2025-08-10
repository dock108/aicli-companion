# Server Authentication Guide

## Overview

The Claude Companion server supports Bearer token authentication to secure API endpoints. Authentication is **optional for local network use** but **required when exposing the server to the internet**.

## Quick Start

### Local Network (No Auth)
```bash
# Default - no authentication required
npm start
```

### Local Network (With Auth)
```bash
# Optional authentication for local use
AUTH_REQUIRED=true AUTH_TOKEN=your-secret-token npm start
```

### Internet Exposure (Auth Required)
```bash
# Authentication automatically required when tunnel is enabled
ENABLE_TUNNEL=true NGROK_AUTH_TOKEN=your-ngrok-token npm start
# Server will generate a secure token if AUTH_TOKEN not provided
```

## Authentication Modes

### 1. Local Network Mode (Default)
- **Auth Required:** No (unless explicitly enabled)
- **Use Case:** Development, home network, trusted environments
- **Configuration:**
  ```env
  AUTH_REQUIRED=false  # Default
  ```

### 2. Authenticated Local Mode
- **Auth Required:** Yes
- **Use Case:** Shared local network, additional security
- **Configuration:**
  ```env
  AUTH_REQUIRED=true
  AUTH_TOKEN=your-secure-token-here
  ```

### 3. Internet Exposed Mode
- **Auth Required:** Yes (automatically enforced)
- **Use Case:** Public access, remote development
- **Configuration:**
  ```env
  ENABLE_TUNNEL=true
  NGROK_AUTH_TOKEN=your-ngrok-auth-token
  AUTH_TOKEN=your-secure-token-here  # Auto-generated if not set
  ```

## How Authentication Works

### Bearer Token
The server uses Bearer token authentication in the `Authorization` header:

```http
Authorization: Bearer your-token-here
```

### Token in Query String (Fallback)
For compatibility, tokens can also be passed as a query parameter:

```
http://server:3001/api/endpoint?token=your-token-here
```

**Note:** Header method is preferred for security.

## iOS App Configuration

### 1. Local Network Connection
No authentication token needed by default:
- Server Address: `192.168.1.100` (your local IP)
- Port: `3001`
- Auth Token: *(leave empty)*

### 2. Authenticated Connection
When server requires authentication:
- Server Address: `192.168.1.100` or public URL
- Port: `3001`
- Auth Token: `your-secure-token-here`

### 3. Public Tunnel Connection
When connecting through ngrok:
- Server Address: *(use the ngrok URL)*
- Auth Token: `your-secure-token-here` *(required)*

## Security Features

### Auto-Enforcement
When `ENABLE_TUNNEL=true`, authentication is automatically required regardless of `AUTH_REQUIRED` setting. This prevents accidentally exposing an unsecured server to the internet.

### Rate Limiting
- **Local:** 100 requests/minute per IP
- **Public:** 50 requests/minute per IP
- **Auth Attempts:** 5 failed attempts per 15 minutes

### Failed Auth Protection
After 10 failed authentication attempts, an IP address is temporarily blocked.

### Timing Attack Prevention
The auth middleware uses constant-time comparison to prevent timing attacks.

## Token Generation

### Automatic Generation
If authentication is required but no token is provided, the server generates a secure random token:

```
🔑 Generated auth token: RaNd0mLy-G3n3rat3d-T0k3n-H3r3
   Save this token to connect mobile clients
```

### Manual Token Setting
Set your own token in the `.env` file:

```env
AUTH_TOKEN=my-super-secret-token-2025
```

### Token Requirements
- Minimum recommended length: 20 characters
- Allowed characters: `a-z`, `A-Z`, `0-9`, `_`, `-`, `=`, `+`, `/`
- Should be kept secret and not committed to version control

## Troubleshooting

### "Authentication required" Error
**Problem:** Server returns 401 Unauthorized

**Solution:** 
1. Check if server has authentication enabled
2. Verify token is correct
3. Ensure token is in Authorization header: `Bearer <token>`

### "Invalid token" Error
**Problem:** Token is provided but rejected

**Solution:**
1. Check for typos in token
2. Ensure no extra spaces or characters
3. Verify token matches server configuration

### Cannot Connect from iOS App
**Problem:** iOS app fails to connect to authenticated server

**Solution:**
1. Update app to latest version with auth support
2. Enter token in Settings > Connection > Auth Token
3. For public URLs, token is required

### Token in Server Logs
**Problem:** Token appears in console output

**Solution:** This is intentional for initial setup. After noting the token:
1. Save it securely
2. Restart server with token in `.env` file
3. Token won't be displayed on subsequent starts

## Best Practices

1. **Use Strong Tokens:** Generate tokens with at least 32 characters
2. **Rotate Regularly:** Change tokens periodically
3. **Use HTTPS:** When exposing publicly, use HTTPS (ngrok provides this)
4. **Monitor Logs:** Check for failed auth attempts
5. **Environment Variables:** Store tokens in `.env` file, not in code
6. **Different Tokens:** Use different tokens for development and production

## Example .env Configuration

```env
# Local development (no auth)
PORT=3001
HOST=0.0.0.0
AUTH_REQUIRED=false

# Local with auth
# AUTH_REQUIRED=true
# AUTH_TOKEN=dev-token-2025-secure

# Public exposure (uncomment for internet access)
# ENABLE_TUNNEL=true
# NGROK_AUTH_TOKEN=2lKjH8...your-ngrok-token
# AUTH_TOKEN=prod-token-super-secure-2025
```

## API Testing with Auth

### With cURL
```bash
# With Bearer token (preferred)
curl -H "Authorization: Bearer your-token-here" http://localhost:3001/api/projects

# With query parameter (fallback)
curl http://localhost:3001/api/projects?token=your-token-here
```

### With HTTPie
```bash
http localhost:3001/api/projects "Authorization: Bearer your-token-here"
```

### With Postman
1. Set request type and URL
2. Go to Authorization tab
3. Select "Bearer Token"
4. Enter your token

## Security Considerations

- **Never** expose server without authentication to the internet
- **Never** commit auth tokens to version control
- **Always** use HTTPS for public endpoints (ngrok provides this)
- **Monitor** authentication logs for suspicious activity
- **Rate limiting** is automatically applied to prevent brute force
- **IP blocking** occurs after multiple failed attempts

---

Last Updated: 2025-08-09