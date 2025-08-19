#!/bin/bash

echo "=== Testing Parallel Project Sessions ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Project A - Message 1
echo -e "${YELLOW}Project A - Message 1 (no session):${NC}"
RESPONSE_A1=$(curl -s -X POST http://localhost:3001/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Project A: Remember APPLE",
    "projectPath": "/tmp/project-a",
    "deviceToken": "test-token"
  }')
echo "$RESPONSE_A1" | jq '.'
SESSION_A=$(echo "$RESPONSE_A1" | jq -r '.sessionId')
echo -e "${GREEN}Session ID: $SESSION_A${NC}"
echo ""

# Wait for processing
sleep 3

# Project B - Message 1  
echo -e "${YELLOW}Project B - Message 1 (no session):${NC}"
RESPONSE_B1=$(curl -s -X POST http://localhost:3001/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "Project B: Remember BANANA",
    "projectPath": "/tmp/project-b",
    "deviceToken": "test-token"
  }')
echo "$RESPONSE_B1" | jq '.'
SESSION_B=$(echo "$RESPONSE_B1" | jq -r '.sessionId')
echo -e "${GREEN}Session ID: $SESSION_B${NC}"
echo ""

# Wait for processing
sleep 3

# Project A - Message 2 (server should have session from previous response)
echo -e "${YELLOW}Project A - Message 2 (server has session):${NC}"
RESPONSE_A2=$(curl -s -X POST http://localhost:3001/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What fruit for Project A?",
    "projectPath": "/tmp/project-a",
    "deviceToken": "test-token"
  }')
echo "$RESPONSE_A2" | jq '.'
echo ""

# Wait for processing
sleep 3

# Project B - Message 2
echo -e "${YELLOW}Project B - Message 2 (server has session):${NC}"
RESPONSE_B2=$(curl -s -X POST http://localhost:3001/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "message": "What fruit for Project B?",
    "projectPath": "/tmp/project-b",
    "deviceToken": "test-token"
  }')
echo "$RESPONSE_B2" | jq '.'
echo ""

echo "=== Test Complete ==="
echo "Expected: Project A should remember APPLE, Project B should remember BANANA"