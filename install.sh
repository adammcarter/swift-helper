#!/bin/bash

# Configuration
REPO_URL="https://github.com/adammcarter/swifthelper.git"
INSTALL_DIR="$HOME/repos/swift-helper"

# ANSI Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting swift-helper installation...${NC}"

# 1. Create ~/repos if needed
mkdir -p "$HOME/repos"

# 2. Clone or Update
if [ -d "$INSTALL_DIR" ]; then
    echo -e "${BLUE}🔄 Updating existing installation at $INSTALL_DIR...${NC}"
    cd "$INSTALL_DIR" || exit 1
    if git pull; then
        echo -e "${GREEN}✅ Update successful.${NC}"
    else
        echo -e "${RED}⚠️ Git pull failed. Continuing with existing version...${NC}"
    fi
else
    echo -e "${BLUE}📦 Cloning swift-helper to $INSTALL_DIR...${NC}"
    if git clone "$REPO_URL" "$INSTALL_DIR"; then
        cd "$INSTALL_DIR" || exit 1
    else
        echo -e "${RED}❌ Git clone failed.${NC}"
        return 1 2>/dev/null || exit 1
    fi
fi

# 3. Build
echo -e "${BLUE}🔨 Building swift-helper (Release)...${NC}"
if swift build -c release; then
    echo -e "${GREEN}✅ Build complete!${NC}"
else
    echo -e "${RED}❌ Build failed.${NC}"
    return 1 2>/dev/null || exit 1
fi

# 4. Change Directory (if sourced)
# We simply execute cd. If run in a subshell (curl | bash), it won't persist.
# If sourced (source <(curl...)), it will persist.
cd "$INSTALL_DIR" || return

echo -e "\n${GREEN}You are now in the swift-helper directory.${NC}"
echo -e "Try running: ${BLUE}swift run swift-helper doctor${NC}"
