# Server Authentication & Internet Exposure Implementation Plan

## 🎯 Mission
Implement secure authentication for the Claude Companion server with automatic enforcement for internet-exposed instances, while maintaining local-first simplicity.

## 📋 Current State
- ✅ Auth middleware exists but has timing issues
- ✅ Bearer token support implemented
- ❌ Auth middleware applied too late in startup
- ❌ No tunneling support for internet exposure
- ❌ iOS settings don't clearly indicate auth requirements
- ❌ No rate limiting for public exposure

## 🏗️ Implementation Plan

### Phase 0: Documentation Setup ✅
**Status:** COMPLETED
- Created new plan.md for server authentication

### Phase 1: Fix Authentication System

#### 1.1 Fix Auth Middleware Timing
**Problem:** Auth middleware is applied after server starts, leaving routes unprotected initially

**Files to modify:**
- `server/src/index.js` - Move auth middleware configuration before route setup
- `server/src/config/middleware-config.js` - Ensure auth applies to all /api routes

**Implementation:**
```javascript
// In index.js constructor, move auth setup BEFORE setupRoutes()
setupBasicMiddleware();
setupAuthMiddleware(); // NEW - configure auth before routes
setupRoutes();
```

#### 1.2 Enhance Authentication Logic
**Principle:** Auth requirements based on exposure
- **Local-only (localhost/LAN):** Auth optional (default: off)
- **Internet-exposed:** Auth mandatory (auto-enforce)

**Files to modify:**
- `server/src/config/server-config.js`:
  ```javascript
  // Add detection for internet exposure
  get isInternetExposed() {
    return process.env.ENABLE_TUNNEL === 'true' || 
           this.host === '0.0.0.0' && process.env.EXPOSE_PUBLIC === 'true';
  }
  
  // Auto-require auth if exposed
  constructor() {
    this.authRequired = this.isInternetExposed || process.env.AUTH_REQUIRED === 'true';
  }
  ```

#### 1.3 Environment Configuration
**File:** `server/.env.example`
```env
# Server Configuration
PORT=5173
HOST=0.0.0.0

# Authentication (optional for local, required for public)
AUTH_REQUIRED=false
AUTH_TOKEN=

# Internet Exposure (auth auto-required when enabled)
ENABLE_TUNNEL=false
TUNNEL_PROVIDER=ngrok
NGROK_AUTH_TOKEN=
```

### Phase 2: Add Tunneling Support

#### 2.1 Create Tunnel Service
**New file:** `server/src/services/tunnel.js`

Features:
- Ngrok integration using `@ngrok/ngrok` package
- Auto-detect when tunnel is active
- Return public URL for iOS app connection
- Future support for Cloudflare Tunnel

#### 2.2 Integrate with Server Startup
**Files to modify:**
- `server/src/index.js`:
  - Check for `ENABLE_TUNNEL` environment variable
  - Start tunnel after server starts
  - Display public URL in console logs
  
- `server/src/config/server-startup.js`:
  - Add tunnel information to startup display
  - Show auth token requirement for public URLs
  - Display QR code for easy mobile connection

#### 2.3 Update Dependencies
**File:** `server/package.json`
```json
{
  "dependencies": {
    "@ngrok/ngrok": "^1.0.0",
    "express-rate-limit": "^7.0.0"
  }
}
```

### Phase 3: iOS App Settings Update

#### 3.1 Enhance Connection Settings
**Files to modify:**
- `ios/Sources/AICLICompanion/SettingsView.swift`:
  - Add "Connection Type" picker:
    - Local Network (no auth by default)
    - Custom Server (optional auth)
    - Public Tunnel (auth required)
  - Show/hide auth token field based on selection
  - Add validation for public URLs requiring auth

#### 3.2 Update Connection Model
**Files to modify:**
- `ios/Sources/AICLICompanion/Models/ServerConnection.swift`:
  ```swift
  enum ConnectionType {
      case local      // 192.168.x.x, 10.x.x.x, localhost
      case custom     // User-provided URL
      case tunnel     // Public ngrok/cloudflare URL
  }
  
  var isAuthRequired: Bool {
      return connectionType == .tunnel || authToken != nil
  }
  ```

#### 3.3 Improve UI/UX
- Clear labeling: "Auth Token (required for public servers)"
- Auto-detect if URL is public (not private IP ranges)
- Warning when connecting to public server without auth
- Success/error feedback for auth validation

### Phase 4: Security Hardening

#### 4.1 Rate Limiting
**New file:** `server/src/middleware/security.js`

Features:
- 100 requests/minute for authenticated users
- 10 requests/minute for non-authenticated (if allowed)
- Block after 5 failed auth attempts
- IP-based tracking with exponential backoff

#### 4.2 Security Headers
**File:** `server/src/config/middleware-config.js`

Enhancements:
- Strict CORS for public exposure
- Enhanced Helmet configuration
- Request size limits (10MB max)
- XSS protection headers

#### 4.3 Monitoring & Logging
- Log all authentication failures
- Track request origins
- Alert on suspicious patterns
- Rate limit violations logged

### Phase 5: Documentation & Testing

#### 5.1 Documentation Updates
**All docs in `/docs` folder:**
- `docs/server/authentication.md` - Complete auth setup guide
- `docs/server/tunneling.md` - Public exposure with ngrok/cloudflare
- `docs/security/best-practices.md` - Security recommendations
- `docs/operations/deployment.md` - Update with auth requirements

#### 5.2 Testing Plan
1. **Local network:** No auth required, works as before
2. **Local with auth:** Optional auth token works correctly
3. **Ngrok tunnel:** Auth automatically required and enforced
4. **iOS connection:** Auth token properly sent in Bearer header
5. **Rate limiting:** Requests blocked after limit exceeded
6. **Security headers:** All headers present in responses

## 📝 Implementation Status

### ✅ Completed
- [x] Created new plan.md document

### 🔄 In Progress
- [ ] Fix auth middleware timing issue

### 📋 Pending
- [ ] Add auth auto-enforcement for public exposure
- [ ] Create tunnel service with ngrok
- [ ] Update iOS settings UI
- [ ] Add rate limiting
- [ ] Create documentation
- [ ] Test all scenarios

## 🔑 Key Principles

1. **Local-first:** Works without auth on local network by default
2. **Secure-by-default:** Auto-requires auth when exposed to internet
3. **User-friendly:** Clear UI indicates when auth is needed
4. **Flexible:** Supports multiple tunneling providers
5. **Safe:** Rate limiting and security headers protect public endpoints

## ✅ Success Criteria

- [ ] Auth middleware protects routes from server start
- [ ] Public exposure auto-requires authentication
- [ ] iOS app handles auth tokens in Bearer headers
- [ ] Settings UI clearly shows auth requirements
- [ ] Ngrok tunnel creates public URL successfully
- [ ] Rate limiting prevents abuse
- [ ] All documentation in `/docs` folder

## 🚨 Potential Issues & Solutions

### Issue: Auth token in URL vs Header
**Solution:** Support both for compatibility, prefer Bearer header

### Issue: Certificate validation for tunnels
**Solution:** Tunnels provide valid HTTPS certificates

### Issue: Rate limiting affects legitimate users
**Solution:** Higher limits for authenticated users

## 📊 Testing Checklist

### Local Testing
- [ ] Server starts without auth on local network
- [ ] Can enable auth optionally for local
- [ ] iOS app connects without auth locally

### Public Testing
- [ ] Ngrok tunnel starts successfully
- [ ] Auth required when tunnel active
- [ ] Unauthorized requests rejected (401)
- [ ] iOS app sends auth token correctly

### Security Testing
- [ ] Rate limiting blocks excessive requests
- [ ] Failed auth attempts tracked
- [ ] Security headers present
- [ ] CORS properly configured

## 🔄 Current Task
**Fixing auth middleware timing issue in server/src/index.js**

---
Last Updated: 2025-08-09
Status: Implementation in progress