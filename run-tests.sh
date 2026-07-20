#!/bin/bash

# Mini-MWAN Test Runner
# Convenient wrapper for running tests with common options

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default options
COVERAGE=false
VERBOSE=false
CONFIG="default"
PATTERN=""

# Parse arguments
while [[ $# -gt 0 ]]; do
	case $1 in
		-c|--coverage)
			COVERAGE=true
			shift
			;;
		-v|--verbose)
			VERBOSE=true
			shift
			;;
		-u|--unit)
			CONFIG="unit"
			shift
			;;
		-i|--integration)
			CONFIG="integration"
			shift
			;;
		-p|--pattern)
			PATTERN="$2"
			shift 2
			;;
		-h|--help)
			echo "Mini-MWAN Test Runner"
			echo ""
			echo "Usage: ./run-tests.sh [options]"
			echo ""
			echo "Options:"
			echo "  -c, --coverage       Run with code coverage"
			echo "  -v, --verbose        Verbose output"
			echo "  -u, --unit           Run only unit tests"
			echo "  -i, --integration    Run only integration tests"
			echo "  -p, --pattern NAME   Run tests matching pattern"
			echo "  -h, --help           Show this help"
			echo ""
			echo "Examples:"
			echo "  ./run-tests.sh                     # Run all tests"
			echo "  ./run-tests.sh -c                  # Run with coverage"
			echo "  ./run-tests.sh -u -v               # Unit tests, verbose"
			echo "  ./run-tests.sh -p 'Gateway'        # Tests matching 'Gateway'"
			echo "  ./run-tests.sh -c && luacov        # Coverage report"
			exit 0
			;;
		*)
			echo -e "${RED}Unknown option: $1${NC}"
			echo "Use --help for usage information"
			exit 1
			;;
	esac
done

# Build busted command
BUSTED_CMD="busted"

# Add config
if [ "$CONFIG" != "default" ]; then
	BUSTED_CMD="$BUSTED_CMD --run=$CONFIG"
fi

# Add coverage
if [ "$COVERAGE" = true ]; then
	BUSTED_CMD="$BUSTED_CMD --coverage"
fi

# Add verbose
if [ "$VERBOSE" = true ]; then
	BUSTED_CMD="$BUSTED_CMD --verbose"
fi

# Add pattern
if [ -n "$PATTERN" ]; then
	BUSTED_CMD="$BUSTED_CMD --filter='$PATTERN'"
fi

# Set test mode environment variable
export MINI_MWAN_TEST_MODE=1

# Print what we're running
echo -e "${YELLOW}Running tests...${NC}"
echo "Command: $BUSTED_CMD"
echo ""

# Run tests
if eval $BUSTED_CMD; then
	echo ""
	echo -e "${GREEN}✓ Tests passed!${NC}"

	# If coverage was requested, generate report
	if [ "$COVERAGE" = true ]; then
		echo ""
		echo -e "${YELLOW}Generating coverage report...${NC}"
		luacov
		echo ""
		echo "Coverage report: luacov.report.out"

		# Show summary
		if command -v grep &> /dev/null; then
			echo ""
			echo -e "${YELLOW}Coverage Summary:${NC}"
			grep "^Summary" -A 10 luacov.report.out || true
		fi
	fi

	exit 0
else
	echo ""
	echo -e "${RED}✗ Tests failed!${NC}"
	exit 1
fi
