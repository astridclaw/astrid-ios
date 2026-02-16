#!/bin/bash

# Localization Validation Script for Astrid iOS
# Checks that all localization files are in sync and properly formatted

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
LOCALIZATIONS_DIR="$PROJECT_DIR/Astrid App/Resources/Localizations"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Supported languages (must match Constants.swift)
LANGUAGES=("en" "es" "fr" "de" "it" "ja" "ko" "nl" "pt" "ru" "zh-Hans" "zh-Hant")

echo -e "${BLUE}=== Localization Validation ===${NC}"
echo ""

ERRORS=0
WARNINGS=0

# Function to extract keys from a .strings file
extract_keys() {
    local file="$1"
    grep -E '^"[^"]+"\s*=' "$file" | sed -E 's/^"([^"]+)".*/\1/' | sort
}

# Function to count keys in a file
count_keys() {
    local file="$1"
    grep -cE '^"[^"]+"\s*=' "$file" || echo 0
}

# Check that all language directories exist
echo -e "${BLUE}Checking language directories...${NC}"
for lang in "${LANGUAGES[@]}"; do
    dir="$LOCALIZATIONS_DIR/${lang}.lproj"
    if [[ ! -d "$dir" ]]; then
        echo -e "${RED}  ERROR: Missing directory for language: $lang${NC}"
        ERRORS=$((ERRORS + 1))
    else
        echo -e "${GREEN}  ✓ $lang.lproj exists${NC}"
    fi
done
echo ""

# Check that all Localizable.strings files exist and are not empty
echo -e "${BLUE}Checking Localizable.strings files...${NC}"
for lang in "${LANGUAGES[@]}"; do
    file="$LOCALIZATIONS_DIR/${lang}.lproj/Localizable.strings"
    if [[ ! -f "$file" ]]; then
        echo -e "${RED}  ERROR: Missing Localizable.strings for: $lang${NC}"
        ERRORS=$((ERRORS + 1))
    elif [[ ! -s "$file" ]]; then
        echo -e "${RED}  ERROR: Empty Localizable.strings for: $lang${NC}"
        ERRORS=$((ERRORS + 1))
    else
        count=$(count_keys "$file")
        echo -e "${GREEN}  ✓ $lang: $count strings${NC}"
    fi
done
echo ""

# Use English as the reference and check for missing keys in other languages
echo -e "${BLUE}Checking for missing translations (vs English)...${NC}"
EN_FILE="$LOCALIZATIONS_DIR/en.lproj/Localizable.strings"
EN_KEYS=$(extract_keys "$EN_FILE")
EN_COUNT=$(echo "$EN_KEYS" | wc -l | tr -d ' ')

for lang in "${LANGUAGES[@]}"; do
    if [[ "$lang" == "en" ]]; then
        continue
    fi

    file="$LOCALIZATIONS_DIR/${lang}.lproj/Localizable.strings"
    if [[ ! -f "$file" ]]; then
        continue
    fi

    LANG_KEYS=$(extract_keys "$file")
    LANG_COUNT=$(echo "$LANG_KEYS" | wc -l | tr -d ' ')

    # Find missing keys (in English but not in this language)
    MISSING=$(comm -23 <(echo "$EN_KEYS") <(echo "$LANG_KEYS"))
    if [[ -z "$MISSING" ]]; then
        MISSING_COUNT=0
    else
        MISSING_COUNT=$(echo "$MISSING" | wc -l | tr -d ' ')
    fi

    # Find extra keys (in this language but not in English)
    EXTRA=$(comm -13 <(echo "$EN_KEYS") <(echo "$LANG_KEYS"))
    if [[ -z "$EXTRA" ]]; then
        EXTRA_COUNT=0
    else
        EXTRA_COUNT=$(echo "$EXTRA" | wc -l | tr -d ' ')
    fi

    if [[ $MISSING_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}  WARNING: $lang is missing $MISSING_COUNT keys${NC}"
        if [[ $MISSING_COUNT -le 10 ]]; then
            echo "$MISSING" | while read key; do
                echo -e "    - $key"
            done
        else
            echo "    (showing first 10)"
            echo "$MISSING" | head -10 | while read key; do
                echo -e "    - $key"
            done
        fi
        WARNINGS=$((WARNINGS + 1))
    fi

    if [[ $EXTRA_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}  WARNING: $lang has $EXTRA_COUNT extra keys not in English${NC}"
        WARNINGS=$((WARNINGS + 1))
    fi

    if [[ $MISSING_COUNT -eq 0 && $EXTRA_COUNT -eq 0 ]]; then
        echo -e "${GREEN}  ✓ $lang: fully synced ($LANG_COUNT keys)${NC}"
    fi
done
echo ""

# Check for syntax errors in .strings files
echo -e "${BLUE}Checking for syntax errors...${NC}"
for lang in "${LANGUAGES[@]}"; do
    file="$LOCALIZATIONS_DIR/${lang}.lproj/Localizable.strings"
    if [[ ! -f "$file" ]]; then
        continue
    fi

    # Check for common syntax issues
    # 1. Lines with = but missing quotes
    BAD_LINES=$(grep -nE '^[^/"]+=' "$file" | grep -vE '^[0-9]+:\s*/\*' || true)
    if [[ -n "$BAD_LINES" ]]; then
        echo -e "${RED}  ERROR: $lang has malformed lines:${NC}"
        echo "$BAD_LINES" | head -5
        ERRORS=$((ERRORS + 1))
    fi

    # 2. Lines with unescaped quotes inside strings (basic check)
    # This is a simplified check - real validation would need a parser

    # If no errors found for this file
    if [[ -z "$BAD_LINES" ]]; then
        echo -e "${GREEN}  ✓ $lang: syntax OK${NC}"
    fi
done
echo ""

# Check that Constants.swift supportedLanguages matches our list
echo -e "${BLUE}Checking Constants.swift matches expected languages...${NC}"
CONSTANTS_FILE="$PROJECT_DIR/Astrid App/Utilities/Constants.swift"
if [[ -f "$CONSTANTS_FILE" ]]; then
    # Extract language codes including those with dashes like zh-Hans
    CONSTANTS_LANGS=$(grep 'supportedLanguages' "$CONSTANTS_FILE" | grep -oE '"[a-zA-Z-]+"' | tr -d '"' | sort)
    EXPECTED_LANGS=$(printf '%s\n' "${LANGUAGES[@]}" | sort)

    if [[ "$CONSTANTS_LANGS" == "$EXPECTED_LANGS" ]]; then
        echo -e "${GREEN}  ✓ Constants.swift supportedLanguages matches${NC}"
    else
        echo -e "${RED}  ERROR: Constants.swift supportedLanguages mismatch${NC}"
        echo "    Expected: $(echo "$EXPECTED_LANGS" | tr '\n' ' ')"
        echo "    Found: $(echo "$CONSTANTS_LANGS" | tr '\n' ' ')"
        ERRORS=$((ERRORS + 1))
    fi
else
    echo -e "${YELLOW}  WARNING: Could not find Constants.swift${NC}"
    WARNINGS=$((WARNINGS + 1))
fi
echo ""

# Summary
echo -e "${BLUE}=== Summary ===${NC}"
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}All localization checks passed!${NC}"
    exit 0
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}Localization checks completed with $WARNINGS warning(s)${NC}"
    exit 0
else
    echo -e "${RED}Localization checks failed with $ERRORS error(s) and $WARNINGS warning(s)${NC}"
    exit 1
fi
