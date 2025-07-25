#!/bin/bash

echo "=== Claude Companion Server Monitor ==="
echo ""
echo "Server Auth Token: 58edc48b71c6070a312f246f133774694785a74d7d37c455f64860158d3ac23a"
echo "Server URL: http://localhost:3001"
echo "WebSocket URL: ws://localhost:3001/ws"
echo ""
echo "=== Server Logs (tail -f server.log) ==="
echo "Press Ctrl+C to stop monitoring"
echo ""
tail -f server.log