#!/bin/bash

# Predeploy Script for Astrid iOS
# Runs all validation checks before deployment

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Default options
RUN_UI_TESTS=false
SKIP_BUILD=false
QUICK_MODE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --full)
            RUN_UI_TESTS=true
            shift
            ;;
        --quick)
            QUICK_MODE=true
            shift
            ;;
        --skip-build)
            SKIP_BUILD=true
            shift
            ;;
        --help)
            echo "Astrid iOS Predeploy Script"
            echo ""
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --full        Run full checks including UI tests"
            echo "  --quick       Run quick checks only (skip tests)"
            echo "  --skip-build  Skip the build verification step"
            echo "  --help        Show this help"
            echo ""
            echo "Default behavior:"
            echo "  - Check localizations"
            echo "  - Run unit tests"
            echo "  - Verify build compiles"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║           Astrid iOS Predeploy Checks                      ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""

STEP=0
TOTAL_STEPS=3
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    TOTAL_STEPS=4
fi
if [[ "$QUICK_MODE" == "true" ]]; then
    TOTAL_STEPS=2
fi

# Step 1: Localization checks
((STEP++))
echo -e "${BLUE}[$STEP/$TOTAL_STEPS] Checking localizations...${NC}"
echo ""
if "$SCRIPT_DIR/check-localizations.sh"; then
    echo -e "${GREEN}✓ Localization checks passed${NC}"
else
    echo -e "${RED}✗ Localization checks failed${NC}"
    exit 1
fi
echo ""

# Step 2: Build verification (unless skipped or quick mode)
if [[ "$SKIP_BUILD" != "true" && "$QUICK_MODE" != "true" ]]; then
    ((STEP++))
    echo -e "${BLUE}[$STEP/$TOTAL_STEPS] Verifying build compiles...${NC}"
    echo ""

    set +e
    xcodebuild build \
        -scheme "Astrid App" \
        -destination "platform=iOS Simulator,name=iPhone 17" \
        -quiet 2>&1

    BUILD_EXIT=$?
    set -e

    if [[ $BUILD_EXIT -eq 0 ]]; then
        echo -e "${GREEN}✓ Build verification passed${NC}"
    else
        echo -e "${RED}✗ Build failed${NC}"
        exit 1
    fi
    echo ""
fi

# Step 3: Unit tests (unless quick mode)
if [[ "$QUICK_MODE" != "true" ]]; then
    ((STEP++))
    echo -e "${BLUE}[$STEP/$TOTAL_STEPS] Running unit tests...${NC}"
    echo ""
    if "$SCRIPT_DIR/run-tests.sh"; then
        echo -e "${GREEN}✓ Unit tests passed${NC}"
    else
        echo -e "${RED}✗ Unit tests failed${NC}"
        exit 1
    fi
    echo ""
fi

# Step 4: UI tests (only with --full)
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    ((STEP++))
    echo -e "${BLUE}[$STEP/$TOTAL_STEPS] Running UI tests...${NC}"
    echo ""
    if "$SCRIPT_DIR/run-tests.sh" --ui --no-unit; then
        echo -e "${GREEN}✓ UI tests passed${NC}"
    else
        echo -e "${RED}✗ UI tests failed${NC}"
        exit 1
    fi
    echo ""
fi

# Quick mode check
if [[ "$QUICK_MODE" == "true" ]]; then
    ((STEP++))
    echo -e "${BLUE}[$STEP/$TOTAL_STEPS] Quick build check...${NC}"
    echo ""

    set +e
    xcodebuild build \
        -scheme "Astrid App" \
        -destination "platform=iOS Simulator,name=iPhone 17" \
        -quiet 2>&1

    BUILD_EXIT=$?
    set -e

    if [[ $BUILD_EXIT -eq 0 ]]; then
        echo -e "${GREEN}✓ Build check passed${NC}"
    else
        echo -e "${RED}✗ Build failed${NC}"
        exit 1
    fi
    echo ""
fi

# Summary
echo ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║  ${GREEN}✓ All predeploy checks passed!${CYAN}                           ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║  Ready to push to main for Xcode Cloud deployment.        ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
