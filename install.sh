#!/bin/bash

# Configuration
REPO_URL="https://github.com/adammcarter/swifthelper.git"

# ANSI Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}🚀 Starting swift-helper installation...${NC}"

# Use a subshell to ensure cleanup and isolation
(
    INSTALL_DIR="$(mktemp -d)"
    # Trap EXIT inside the subshell handles cleanup when the subshell ends
    trap 'rm -rf "$INSTALL_DIR"' EXIT
    
    # 1. Get Source
    if [ -f "./Package.swift" ]; then
        echo -e "${BLUE}📂 Found Package.swift, installing from local source...${NC}"
        # Copy source to temp dir, excluding build artifacts and git history
        tar --exclude='./.build' --exclude='./.git' -cf - . | (cd "$INSTALL_DIR" && tar xf -)
    else
        echo -e "${BLUE}📦 Cloning swift-helper...${NC}"
        if ! git clone "$REPO_URL" "$INSTALL_DIR" > /dev/null 2>&1; then
            echo -e "${RED}❌ Git clone failed.${NC}"
            exit 1
        fi
    fi
    
    # 2. Build
    # Enter build directory
    cd "$INSTALL_DIR" || exit 1
        
    echo -e "${BLUE}🔨 Building swift-helper (Release)...${NC}"
    if ! swift build -c release; then
        echo -e "${RED}❌ Build failed.${NC}"
        exit 1
    fi
    
    # 3. Install
    BINARY_PATH=".build/release/swift-helper"
    TARGET_DIR="/usr/local/bin"
    TARGET_BIN="$TARGET_DIR/swift-helper"
    
    if [ ! -f "$BINARY_PATH" ]; then
        echo -e "${RED}❌ Binary not found at $BINARY_PATH${NC}"
        exit 1
    fi
    
    SUCCESS=0
    
    # Try /usr/local/bin (writable?)
    if [ -w "$TARGET_DIR" ] && cp "$BINARY_PATH" "$TARGET_BIN"; then
        echo -e "${GREEN}✅ Installed to $TARGET_BIN${NC}"
        SUCCESS=1
    elif sudo cp "$BINARY_PATH" "$TARGET_BIN"; then
         sudo chmod +x "$TARGET_BIN"
         echo -e "${GREEN}✅ Installed to $TARGET_BIN${NC}"
         SUCCESS=1
    else
        # Fallback to ~/.local/bin
        TARGET_DIR="$HOME/.local/bin"
        TARGET_BIN="$TARGET_DIR/swift-helper"
        
        mkdir -p "$TARGET_DIR"
        if cp "$BINARY_PATH" "$TARGET_BIN"; then
             chmod +x "$TARGET_BIN"
             echo -e "${GREEN}✅ Installed to $TARGET_BIN${NC}"
             SUCCESS=1
             
             # Check PATH for fallback
            if [[ ":$PATH:" != *":$TARGET_DIR:"* ]]; then
                echo -e "${RED}⚠️  Note: $TARGET_DIR is not in your PATH.${NC}"
                echo -e "   Run: echo 'export PATH=\"\$HOME/.local/bin:\$PATH\"' >> ~/.zshrc && source ~/.zshrc"
            fi
        fi
    fi
    
    if [ "$SUCCESS" != "1" ]; then
        echo -e "${RED}❌ Installation failed.${NC}"
        exit 1
    fi
)

if [ $? -eq 0 ]; then
    echo -e "Try running: ${BLUE}swift-helper doctor${NC}"
else
    return 1 2>/dev/null || exit 1
fi
