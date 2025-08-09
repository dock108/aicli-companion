# APNS Keys Directory

This directory contains Apple Push Notification Service (APNS) keys.

## Files
- `AuthKey_2Y226B9433.p8` - APNS authentication key

## Security Note
These files contain sensitive authentication keys and are excluded from git via `.gitignore`.

## Setup
The server will automatically use the key in this directory. No additional configuration needed unless you want to override the path via environment variables.