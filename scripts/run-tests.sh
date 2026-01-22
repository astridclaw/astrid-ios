#!/bin/bash

# Test Runner Script for Astrid iOS
# Runs unit tests and optionally UI tests

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Default options
RUN_UNIT_TESTS=true
RUN_UI_TESTS=false
QUIET_MODE=true
DESTINATION="platform=iOS Simulator,name=iPhone 17"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --ui)
            RUN_UI_TESTS=true
            shift
            ;;
        --no-unit)
            RUN_UNIT_TESTS=false
            shift
            ;;
        --verbose)
            QUIET_MODE=false
            shift
            ;;
        --destination)
            DESTINATION="$2"
            shift 2
            ;;
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "  --ui          Also run UI tests (slower)"
            echo "  --no-unit     Skip unit tests"
            echo "  --verbose     Show full xcodebuild output"
            echo "  --destination Set simulator destination (default: iPhone 17)"
            echo "  --help        Show this help"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

cd "$PROJECT_DIR"

echo -e "${BLUE}=== Astrid iOS Test Runner ===${NC}"
echo ""

QUIET_FLAG=""
if [[ "$QUIET_MODE" == "true" ]]; then
    QUIET_FLAG="-quiet"
fi

# Run unit tests
if [[ "$RUN_UNIT_TESTS" == "true" ]]; then
    echo -e "${BLUE}Running unit tests...${NC}"
    echo "  Destination: $DESTINATION"
    echo ""

    set +e
    if [[ "$QUIET_MODE" == "true" ]]; then
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" \
            -quiet 2>&1 | tee /tmp/unit_tests.log

        UNIT_EXIT=${PIPESTATUS[0]}
    else
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppTests" 2>&1 | tee /tmp/unit_tests.log

        UNIT_EXIT=${PIPESTATUS[0]}
    fi
    set -e

    if [[ $UNIT_EXIT -eq 0 ]]; then
        # Count passed tests
        PASSED=$(grep -c "passed" /tmp/unit_tests.log 2>/dev/null || echo 0)
        SKIPPED=$(grep -c "skipped" /tmp/unit_tests.log 2>/dev/null || echo 0)
        echo ""
        echo -e "${GREEN}✓ Unit tests passed ($PASSED passed, $SKIPPED skipped)${NC}"
    else
        echo ""
        echo -e "${RED}✗ Unit tests failed${NC}"
        # Show failures
        grep -E "(failed|error:)" /tmp/unit_tests.log | head -20 || true
        exit 1
    fi
    echo ""
fi

# Run UI tests
if [[ "$RUN_UI_TESTS" == "true" ]]; then
    echo -e "${BLUE}Running UI tests...${NC}"
    echo "  Destination: $DESTINATION"
    echo "  (This may take a few minutes)"
    echo ""

    set +e
    if [[ "$QUIET_MODE" == "true" ]]; then
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppUITests" \
            -quiet 2>&1 | tee /tmp/ui_tests.log

        UI_EXIT=${PIPESTATUS[0]}
    else
        xcodebuild test \
            -scheme "Astrid App" \
            -destination "$DESTINATION" \
            -only-testing:"Astrid AppUITests" 2>&1 | tee /tmp/ui_tests.log

        UI_EXIT=${PIPESTATUS[0]}
    fi
    set -e

    if [[ $UI_EXIT -eq 0 ]]; then
        PASSED=$(grep -c "passed" /tmp/ui_tests.log 2>/dev/null || echo 0)
        SKIPPED=$(grep -c "skipped" /tmp/ui_tests.log 2>/dev/null || echo 0)
        echo ""
        echo -e "${GREEN}✓ UI tests passed ($PASSED passed, $SKIPPED skipped)${NC}"
    else
        echo ""
        echo -e "${RED}✗ UI tests failed${NC}"
        grep -E "(failed|error:)" /tmp/ui_tests.log | head -20 || true
        exit 1
    fi
    echo ""
fi

echo -e "${GREEN}=== All tests passed! ===${NC}"
