#!/bin/bash

# Crawlens - Database Reset and Setup Script
# This script resets the database and creates default admin/org

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

echo -e "${BLUE}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                                                               ║"
echo "║     🗄️  Crawlens - Database Reset & Setup                   ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

cd "$PROJECT_ROOT"

# Check if docker is running
if ! docker info >/dev/null 2>&1; then
    echo -e "${RED}❌ Docker is not running. Please start Docker first.${NC}"
    exit 1
fi

# Parse arguments
SKIP_CONFIRM=false
CUSTOM_EMAIL=""
CUSTOM_PASSWORD=""

while [[ $# -gt 0 ]]; do
    case $1 in
        -y|--yes)
            SKIP_CONFIRM=true
            shift
            ;;
        --email)
            CUSTOM_EMAIL="$2"
            shift 2
            ;;
        --password)
            CUSTOM_PASSWORD="$2"
            shift 2
            ;;
        -h|--help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  -y, --yes         Skip confirmation prompt"
            echo "  --email EMAIL     Custom admin email"
            echo "  --password PASS   Custom admin password"
            echo "  -h, --help        Show this help"
            echo ""
            echo "Default credentials:"
            echo "  Email:    admin@crawlens.local"
            echo "  Password: admin123"
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            exit 1
            ;;
    esac
done

# Confirmation
if [ "$SKIP_CONFIRM" = false ]; then
    echo -e "${YELLOW}⚠️  WARNING: This will DELETE ALL DATA in the database!${NC}"
    echo ""
    read -p "Are you sure you want to continue? (y/N) " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo -e "${RED}❌ Aborted${NC}"
        exit 1
    fi
fi

echo ""
echo -e "${YELLOW}🗑️  Resetting database...${NC}"

# Drop all collections
docker compose exec -T mongodb mongosh crawlens --eval "
    db.users.drop();
    db.organizations.drop();
    db.members.drop();
    db.projects.drop();
    db.urls.drop();
    db.snapshots.drop();
    db.workflows.drop();
    db.batch_runs.drop();
    print('Collections dropped successfully');
" 2>/dev/null || true

echo -e "${GREEN}   ✅ Database reset complete${NC}"

echo ""
echo -e "${YELLOW}🔧 Running setup script...${NC}"

# Build setup command
SETUP_CMD="python -m app.scripts.setup_dev"
if [ -n "$CUSTOM_EMAIL" ]; then
    SETUP_CMD="$SETUP_CMD --email $CUSTOM_EMAIL"
fi
if [ -n "$CUSTOM_PASSWORD" ]; then
    SETUP_CMD="$SETUP_CMD --password $CUSTOM_PASSWORD"
fi

# Run setup script inside server container
docker compose exec -T server $SETUP_CMD

echo ""
echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════════╗"
echo "║                    ✅ Setup Complete!                         ║"
echo "╠═══════════════════════════════════════════════════════════════╣"
echo "║                                                               ║"
echo "║   🌐 Frontend:    http://localhost:3000                       ║"
echo "║   📚 API Docs:    http://localhost:8000/docs                  ║"
echo "║                                                               ║"
echo "║   📧 Email:       admin@crawlens.local                       ║"
echo "║   🔑 Password:    admin123                                    ║"
echo "║                                                               ║"
echo "╚═══════════════════════════════════════════════════════════════╝"
echo -e "${NC}"
