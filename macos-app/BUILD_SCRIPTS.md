# Build & Test Scripts for macOS App

These scripts help avoid constant password prompts during development and testing.

## Quick Start

### For Testing Without Password Prompts

1. **Simplest Option - No Code Signing** (Recommended for local testing):
   ```bash
   ./test-no-sign.sh
   ```
   This runs tests without code signing - fastest for development.

2. **With Password Once Per Session**:
   ```bash
   ./unlock-keychain.sh
   # Enter password when prompted
   # Keychain stays unlocked for 3 hours
   
   # Then run tests normally:
   xcodebuild test -project AICLICompanionHost.xcodeproj -scheme AICLICompanionHost -destination 'platform=macOS'
   ```

3. **Using Environment Variables** (Best for CI/automation):
   ```bash
   # Create .env file (already in .gitignore)
   cp .env.example .env
   # Edit .env and add your keychain password
   
   # Run tests with automatic unlock:
   ./test-with-env.sh
   ```

## Script Descriptions

### `unlock-keychain.sh`
- Unlocks the keychain for 3 hours
- Grants codesigning access without prompts
- Run once per session

### `test-no-sign.sh`
- Runs tests without code signing
- Fastest option for local development
- No password required

### `test-with-auth.sh`
- Unlocks keychain and runs tests
- Pass password as argument or enter when prompted
- Includes proper code signing

### `test-with-env.sh`
- Uses .env file for credentials
- Best for automation and CI
- Supports all build settings via environment variables

## Security Notes

- Never commit `.env` file (it's in .gitignore)
- The scripts don't store passwords permanently
- Keychain auto-locks after timeout (3 hours by default)
- For CI, use secure environment variables

## Troubleshooting

If you still get password prompts:
1. Make sure the keychain is unlocked: `security unlock-keychain`
2. Reset key partition list: Run `unlock-keychain.sh` again
3. Check code signing settings in Xcode project

## For GitHub Actions CI

Add these secrets to your repository:
- `KEYCHAIN_PASSWORD` - Your macOS keychain password
- `DEVELOPMENT_TEAM` - Your Apple Developer Team ID (XC52SAFE3Z)

Then in your workflow:
```yaml
- name: Unlock Keychain
  env:
    KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
  run: |
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" ~/Library/Keychains/login.keychain-db
```