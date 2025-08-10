#!/bin/bash

echo "Claude Companion Server Authentication & Tunnel Test"
echo "===================================================="

# Check app settings
echo -e "\n📱 macOS App Settings:"
echo -n "  requireAuthentication: "
defaults read com.claude.companion.host requireAuthentication 2>/dev/null || echo "not set"
echo -n "  enableTunnel: "
defaults read com.claude.companion.host enableTunnel 2>/dev/null || echo "not set"
echo -n "  ngrokAuthToken: "
if defaults read com.claude.companion.host ngrokAuthToken 2>/dev/null | grep -q "[a-zA-Z0-9]"; then
    echo "configured ✓"
else
    echo "not set"
fi

# Wait for server
echo -e "\n🔄 Checking server status..."
for i in {1..10}; do
    if curl -s http://localhost:3001/health > /dev/null 2>&1; then
        echo "✅ Server is running on port 3001"
        break
    fi
    if [ $i -eq 10 ]; then
        echo "❌ Server is not running"
        echo "   Please start the server from the macOS menu bar app"
        exit 1
    fi
    sleep 1
done

# Test authentication
echo -e "\n🔐 Testing authentication..."
response=$(curl -s -w "\nHTTP_STATUS:%{http_code}" http://localhost:3001/api/status 2>/dev/null)
http_status=$(echo "$response" | grep "HTTP_STATUS:" | cut -d: -f2)
content=$(echo "$response" | grep -v "HTTP_STATUS:")

if [ "$http_status" = "401" ]; then
    echo "✅ Authentication is ENABLED (401 Unauthorized)"
    echo "   To test with token:"
    echo "   1. Get token from Settings → Security tab"
    echo "   2. Run: curl -H 'Authorization: Bearer <token>' http://localhost:3001/api/status"
elif [ "$http_status" = "200" ]; then
    echo "⚠️  Authentication is DISABLED (200 OK)"
    echo "   To enable:"
    echo "   1. Open Settings → Security tab"
    echo "   2. Enable 'Require Authentication'"
    echo "   3. Click 'Restart Now' when prompted"
fi

# Check for tunnel
echo -e "\n🌐 Checking tunnel status..."
ps aux | grep -E "ngrok|cloudflared" | grep -v grep > /dev/null
if [ $? -eq 0 ]; then
    echo "✅ Tunnel process is running"
    # Try to get public URL from server logs or process
    public_url=$(lsof -i :3001 2>/dev/null | grep ngrok | head -1)
    if [ ! -z "$public_url" ]; then
        echo "   Public URL may be available in the app"
    fi
else
    echo "ℹ️  No tunnel process found"
    echo "   To enable:"
    echo "   1. Open Settings → Security tab"
    echo "   2. Enable 'Enable Internet Access'"
    echo "   3. Enter ngrok auth token"
    echo "   4. Click 'Restart Now' when prompted"
fi

echo -e "\n✨ Test complete!"