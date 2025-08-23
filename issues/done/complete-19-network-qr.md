# Issue #19: QR Code Scanner Not Working with Ngrok URLs

**Priority**: High  
**Component**: Server - QR Generation & iOS QR Scanner  
**Beta Blocker**: Yes (Blocks remote testing scenarios)  
**Discovered**: 2025-08-21  
**Status**: RESOLVED ✅  
**Resolved**: 2025-08-21

## Problem Description

The QR code scanner appears to have issues connecting to servers using Ngrok URLs. This blocks remote testing and development scenarios where developers need to connect their iOS app to a server exposed via Ngrok tunnel. The issue may be in:
1. QR code generation not properly encoding Ngrok URLs ✅ FIXED
2. iOS scanner not correctly parsing Ngrok URLs ✅ VERIFIED WORKING
3. Auth token extraction failing with Ngrok URLs ✅ VERIFIED WORKING
4. TLS/HTTPS handling with Ngrok tunnels ✅ VERIFIED WORKING

**Root Cause Found**: The server's `/api/auth/setup` endpoint was only generating QR codes with local IP addresses and completely ignoring active Ngrok tunnel URLs.

## Investigation Results

### Server QR Generation Issue (ROOT CAUSE)
- `/server/src/routes/auth.js` was only using local IP addresses for QR code generation
- The tunnel service was imported but never checked for active tunnel URLs
- QR codes always contained local IPs even when Ngrok was running

### iOS QR Scanner (NO ISSUES)
- QR scanner properly accepts and parses raw URL strings
- `parseConnectionString()` correctly handles both http and https URLs
- Properly extracts host, port, and auth token from query parameters
- Works with both local IPs and domain names (including Ngrok domains)
- Uses appropriate default ports (443 for https, 80 for http)

## Solution Implemented

Modified `/server/src/routes/auth.js` to prioritize tunnel URLs when available:

### Code Changes

**File Modified**: `/server/src/routes/auth.js`

**Key Changes**:
1. Check `tunnelService.getPublicUrl()` before falling back to local IPs
2. Use tunnel URL for QR code generation when available
3. Extract host from tunnel URL for display
4. Properly handle auth token as query parameter in tunnel URLs
5. Return tunnel connection in `availableAddresses` array

**Before**:
```javascript
// Always used local IP addresses
const addresses = getLocalIPAddresses();
const primaryAddress = addresses[0]?.address || 'localhost';
const protocol = enableTLS ? 'https' : 'http';
connectionUrl = `${protocol}://${primaryAddress}:${port}`;
```

**After**:
```javascript
// Check if tunnel is active - PRIORITIZE TUNNEL URL
const tunnelUrl = tunnelService.getPublicUrl();
if (tunnelUrl) {
  // Use tunnel URL when available
  connectionUrl = tunnelUrl;
  protocol = tunnelUrl.startsWith('https') ? 'https' : 'http';
  
  // Extract host from tunnel URL for display
  try {
    const url = new URL(tunnelUrl);
    primaryAddress = url.host;
  } catch (e) {
    primaryAddress = tunnelUrl.replace(/^https?:\/\//, '').split('/')[0];
  }
  
  logger.info('Using tunnel URL for QR code', { tunnelUrl, authRequired });
} else {
  // Fall back to local IP addresses only if no tunnel
  primaryAddress = addresses[0]?.address || 'localhost';
  protocol = enableTLS ? 'https' : 'http';
  connectionUrl = `${protocol}://${primaryAddress}:${port}`;
}
```

## Testing Requirements

### Manual Testing Steps
1. Start server with Ngrok tunnel enabled:
   ```bash
   ENABLE_TUNNEL=true TUNNEL_PROVIDER=ngrok NGROK_AUTH_TOKEN=your_token npm start
   ```

2. Verify server logs show tunnel URL:
   ```
   ✅ Ngrok tunnel established: https://abc123.ngrok.app
   Using tunnel URL for QR code
   ```

3. Generate QR code via `/api/auth/setup` endpoint
4. Verify QR code contains Ngrok URL, not local IP
5. Scan QR code with iOS app
6. Verify successful connection to server via Ngrok

### Test Scenarios
- ✅ QR generation with active Ngrok tunnel
- ✅ QR generation without tunnel (fallback to local IP)
- ✅ Auth token included in QR with tunnel URL
- ✅ iOS scanner parsing Ngrok URLs
- ✅ Connection establishment via Ngrok

## Result

QR code scanner now properly works with Ngrok URLs. When a tunnel is active, the QR code will contain the public Ngrok URL instead of local IP addresses, enabling remote testing and development scenarios. The iOS app correctly parses and connects to these Ngrok URLs without any modifications needed on the client side.