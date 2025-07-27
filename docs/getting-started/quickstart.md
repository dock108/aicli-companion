# Quick Start Guide

Get Claude Companion up and running in 5 minutes!

## 1. Start the Server

```bash
# If installed globally
claude-companion-server

# Or from source
cd server && npm start
```

You should see:
```
🚀 Claude Companion Server v1.0.0
📡 Server running on http://localhost:3001
🔐 Auth token required: true
📢 Bonjour broadcasting as: claude-companion-3001
```

## 2. Connect from iOS

1. **Launch the app** on your iOS device
2. **Tap Settings** (gear icon)
3. **Enable Auto-Discovery** - your server should appear
4. **Enter your auth token** (from server startup or `.env`)
5. **Tap "Test Connection"** - should show success
6. **Save** the connection

## 3. Start Chatting

1. **Return to Chat** screen
2. **Set working directory** (tap folder icon)
3. **Type a message**: "What files are in this directory?"
4. **Send** and watch Claude respond!

## Common First Commands

Try these to get familiar with Claude Companion:

```
"List all JavaScript files in this project"
"Show me the package.json file"
"What does this project do?"
"Run npm test and show me the results"
```

## Using with Existing Projects

1. **Navigate to your project**:
   ```bash
   cd /path/to/your/project
   ```

2. **Start server with working directory**:
   ```bash
   claude-companion-server --cwd .
   ```

3. **Connect from iOS** and you're ready to code!

## Quick Tips

- **Offline Mode**: Messages queue when disconnected
- **Tool Indicators**: Watch for file/command activity
- **Conversation History**: Swipe down to search past chats
- **File Browser**: Tap 📁 to browse and select files
- **Multiple Sessions**: Premium supports 5 concurrent sessions

## Desktop Host App (Optional)

For a GUI interface to manage the server:

```bash
cd server/hostapp
npm run tauri dev
```

This provides:
- Visual server controls
- QR code for easy mobile connection
- Log viewing
- Configuration management

## What's Next?

- **Explore Features**: Check the [Architecture Overview](../architecture/overview.md)
- **Learn the API**: Read the [WebSocket Protocol](../api/websocket-api.md)
- **Customize**: See [Development Setup](../development/setup.md)
- **Deploy**: Follow the [Deployment Guide](../operations/deployment.md)

## Need Help?

- **Connection Issues?** See [Troubleshooting](./troubleshooting.md)
- **API Questions?** Check [REST API](../api/rest-api.md)
- **Report Bugs**: [GitHub Issues](https://github.com/your-repo/claude-companion/issues)

---

**Last Updated**: 2025-07-27