#!/bin/bash

# Crawlens - First Time Setup Script
# This script sets up the project for first-time use

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

cd "$PROJECT_ROOT"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║     🔧 Crawlens - First Time Setup                          ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Create environment files
echo -e "${YELLOW}📝 Creating environment files...${NC}"

# Root dev envs
if [ ! -f "$PROJECT_ROOT/.env.development" ] && [ -f "$PROJECT_ROOT/.env.development.example" ]; then
    cp "$PROJECT_ROOT/.env.development.example" "$PROJECT_ROOT/.env.development"
    echo -e "${GREEN}   ✓ Created .env.development${NC}"
else
    echo -e "${BLUE}   ℹ .env.development already exists (or template missing)${NC}"
fi

if [ ! -f "$PROJECT_ROOT/.env" ] && [ -f "$PROJECT_ROOT/.env.development.example" ]; then
    cp "$PROJECT_ROOT/.env.development.example" "$PROJECT_ROOT/.env"
    echo -e "${GREEN}   ✓ Created .env${NC}"
else
    echo -e "${BLUE}   ℹ .env already exists${NC}"
fi

# Server dev env
if [ ! -f "$PROJECT_ROOT/server/.env" ] && [ -f "$PROJECT_ROOT/server/.env.development.example" ]; then
    cp "$PROJECT_ROOT/server/.env.development.example" "$PROJECT_ROOT/server/.env"
    echo -e "${GREEN}   ✓ Created server/.env${NC}"
else
    echo -e "${BLUE}   ℹ server/.env already exists${NC}"
fi

# Client env
if [ ! -f "$PROJECT_ROOT/client/.env.local" ] && [ -f "$PROJECT_ROOT/client/.env.local.example" ]; then
    cp "$PROJECT_ROOT/client/.env.local.example" "$PROJECT_ROOT/client/.env.local"
    echo -e "${GREEN}   ✓ Created client/.env.local${NC}"
else
    echo -e "${BLUE}   ℹ client/.env.local already exists${NC}"
fi
if [ ! -f "$PROJECT_ROOT/client/.env" ] && [ -f "$PROJECT_ROOT/client/.env.local.example" ]; then
    cp "$PROJECT_ROOT/client/.env.local.example" "$PROJECT_ROOT/client/.env"
    echo -e "${GREEN}   ✓ Created client/.env${NC}"
else
    echo -e "${BLUE}   ℹ client/.env already exists${NC}"
fi

# Landing env
if [ ! -f "$PROJECT_ROOT/landingpage/.env.local" ] && [ -f "$PROJECT_ROOT/landingpage/.env.local.example" ]; then
    cp "$PROJECT_ROOT/landingpage/.env.local.example" "$PROJECT_ROOT/landingpage/.env.local"
    echo -e "${GREEN}   ✓ Created landingpage/.env.local${NC}"
else
    echo -e "${BLUE}   ℹ landingpage/.env.local already exists${NC}"
fi
if [ ! -f "$PROJECT_ROOT/landingpage/.env" ] && [ -f "$PROJECT_ROOT/landingpage/.env.local.example" ]; then
    cp "$PROJECT_ROOT/landingpage/.env.local.example" "$PROJECT_ROOT/landingpage/.env"
    echo -e "${GREEN}   ✓ Created landingpage/.env${NC}"
else
    echo -e "${BLUE}   ℹ landingpage/.env already exists${NC}"
fi

# Create directories
echo -e "\n${YELLOW}📁 Creating directories...${NC}"

mkdir -p "$PROJECT_ROOT/server/storage/screenshots"
mkdir -p "$PROJECT_ROOT/server/storage/html"
mkdir -p "$PROJECT_ROOT/data/mongodb"
mkdir -p "$PROJECT_ROOT/data/redis"

echo -e "${GREEN}   ✓ Storage directories created${NC}"

# Make scripts executable
echo -e "\n${YELLOW}🔐 Making scripts executable...${NC}"
chmod +x "$SCRIPT_DIR"/*.sh
echo -e "${GREEN}   ✓ Scripts are now executable${NC}"

# Check Docker
echo -e "\n${YELLOW}🐳 Checking Docker...${NC}"
if command -v docker >/dev/null 2>&1; then
    echo -e "${GREEN}   ✓ Docker is installed${NC}"
    
    if docker info >/dev/null 2>&1; then
        echo -e "${GREEN}   ✓ Docker daemon is running${NC}"
    else
        echo -e "${YELLOW}   ⚠ Docker daemon is not running. Start Docker Desktop first.${NC}"
    fi
else
    echo -e "${RED}   ✗ Docker is not installed. Please install Docker first.${NC}"
    echo -e "     Download from: https://www.docker.com/products/docker-desktop"
fi

# Summary
echo -e "\n${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ Setup Complete!                         ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║                                                               ║"
echo "║   Next Steps:                                                 ║"
echo "║                                                               ║"
echo "║   1. Make sure Docker Desktop is running                      ║"
echo "║                                                               ║"
echo "║   2. Start the application:                                   ║"
echo "║      $ ./scripts/start.sh                                     ║"
echo "║                                                               ║"
echo "║   3. Open your browser:                                       ║"
echo "║      • App:          http://localhost:3000                    ║"
echo "║      • Landing Page: http://localhost:3410                    ║"
echo "║      • API Docs:     http://localhost:8000/docs               ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
