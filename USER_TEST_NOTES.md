# User Test Notes

## Active Issues

All numbered issues have been migrated to individual files in the `issues/` directory.

To view active issues, check the `issues/` folder. Files without the `complete-` prefix are active issues.

---

## Critical Testing Requirements

### Authentication Testing Matrix (MUST TEST BEFORE BETA)
**Added**: 2025-08-21  
**Priority**: CRITICAL - Must be thoroughly tested before beta release

#### Test Scenarios to Execute:

**1. Server Configuration Tests**
- [ ] Server with `AUTH_REQUIRED=false` (default)
  - iOS app should connect without any auth
  - All features should work normally
  
- [ ] Server with `AUTH_REQUIRED=true` and valid `AUTH_TOKEN` set
  - iOS app WITHOUT token configured → Should show auth error
  - iOS app WITH correct token → Should connect successfully
  - iOS app WITH incorrect token → Should show auth error
  
- [ ] Server with `AUTH_REQUIRED=true` but NO `AUTH_TOKEN` set
  - Server should fail to start with clear error message

**2. iOS App Configuration Tests**
- [ ] No auth token in settings (default)
  - Should work with non-auth server
  - Should fail gracefully with auth-required server
  
- [ ] Valid auth token in settings
  - Should work with matching auth server
  - Should still work with non-auth server
  
- [ ] Invalid/wrong auth token in settings
  - Should fail with clear error on auth server
  - Should still work with non-auth server (token ignored)
  
- [ ] Malformed auth token (special characters, spaces, etc.)
  - Should handle gracefully without crashing

**3. Connection Flow Tests**
- [ ] Start server with auth, connect iOS without token
  - Should see clear "Authentication Required" message
  - Should NOT crash or hang
  
- [ ] Start server with auth, connect iOS with wrong token
  - Should see "Invalid Token" or similar error
  - Should allow retry with different token
  
- [ ] Switch server from non-auth to auth while app connected
  - Should handle gracefully (disconnect/reconnect flow)
  
- [ ] Switch server from auth to non-auth while app connected
  - Should continue working

**4. WebSocket Specific Tests**
- [ ] Test WebSocket connection with auth token in header
- [ ] Test WebSocket reconnection after auth failure
- [ ] Test WebSocket with expired/rotated tokens
- [ ] Test multiple iOS clients with same token (should work)
- [ ] Test multiple iOS clients with different tokens

**5. Error Message Tests**
- [ ] Verify all auth errors show user-friendly messages
- [ ] No token leakage in error messages
- [ ] Clear instructions on how to add token in settings
- [ ] No infinite retry loops on auth failure

**6. Edge Cases**
- [ ] Server crashes and restarts with different auth config
- [ ] Token with maximum length (test limits)
- [ ] Empty string as token (should be treated as no token)
- [ ] Token rotation while clients connected
- [ ] Network interruption during auth handshake
- [ ] Server behind proxy with auth headers stripped

**7. Security Tests**
- [ ] Token not visible in logs (server or client)
- [ ] Token not stored in plain text on iOS (should use Keychain)
- [ ] Token not sent to non-auth servers
- [ ] Token not included in crash reports or analytics
- [ ] HTTPS/WSS only when auth is enabled (no plain HTTP/WS)

#### Testing Commands:

```bash
# Start server WITHOUT auth (default)
npm start

# Start server WITH auth
AUTH_REQUIRED=true AUTH_TOKEN=test-token-12345 npm start

# Test with wrong token
curl -H "Authorization: Bearer wrong-token" http://localhost:3000/api/health

# Test with correct token
curl -H "Authorization: Bearer test-token-12345" http://localhost:3000/api/health

# Test WebSocket with auth
wscat -c ws://localhost:3000 -H "Authorization: Bearer test-token-12345"
```

#### Expected Behaviors:

✅ **Success Cases:**
- Non-auth server + iOS without token = Works
- Auth server + iOS with matching token = Works
- Clear error messages for all failure cases
- Graceful degradation, no crashes

❌ **Failure Cases to Verify:**
- Auth server + iOS without token = Clear auth required message
- Auth server + iOS with wrong token = Clear invalid token message
- Malformed tokens = Handled gracefully
- Token in wrong format = Clear format error

#### Post-Test Checklist:
- [ ] All auth combinations tested
- [ ] No security vulnerabilities found
- [ ] Error messages are user-friendly
- [ ] No token leakage anywhere
- [ ] Documentation updated with auth setup
- [ ] Settings UI clearly shows auth status

---

## Testing Protocol

### How to Document New Issues
When discovering issues during user testing, add them to the `issues/` directory using the template at `issues/template.md`.

File naming: `issues/[number]-[brief-description].md`

---

**Document Created**: 2025-08-19  
**Last Updated**: 2025-08-22 (Migrated all numbered issues to individual files)