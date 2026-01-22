#!/bin/bash
#
# Dockerfile Analyzer
# Checks for common issues, anti-patterns, and optimization opportunities
#
# Usage: ./analyze-dockerfile.sh <path-to-dockerfile>

set -e

DOCKERFILE="${1:-Dockerfile}"
ERRORS=0
WARNINGS=0

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
    ((ERRORS++))
}

print_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
    ((WARNINGS++))
}

print_ok() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Check if file exists
if [[ ! -f "$DOCKERFILE" ]]; then
    echo -e "${RED}Error: Dockerfile not found at '$DOCKERFILE'${NC}"
    exit 1
fi

echo -e "${BLUE}Analyzing: $DOCKERFILE${NC}"
echo "=========================================="

# Read the Dockerfile
CONTENT=$(cat "$DOCKERFILE")

print_header "Security Checks"

# Check for USER instruction
if grep -q "^USER " "$DOCKERFILE"; then
    USER_LINE=$(grep "^USER " "$DOCKERFILE" | tail -1)
    if echo "$USER_LINE" | grep -qE "USER (root|0)"; then
        print_warning "USER is set to root - consider using non-root user"
    else
        print_ok "Non-root USER configured"
    fi
else
    print_error "No USER instruction found - container will run as root"
fi

# Check for :latest tag
if grep -qE "^FROM .+:latest" "$DOCKERFILE"; then
    print_error "Using :latest tag - pin to specific version for reproducibility"
elif grep -qE "^FROM [^:]+$" "$DOCKERFILE"; then
    print_error "No tag specified (defaults to :latest) - pin to specific version"
else
    print_ok "Base image uses specific tag"
fi

# Check for hardcoded secrets patterns
if grep -qiE "(password|secret|api.?key|token)=" "$DOCKERFILE"; then
    print_error "Possible hardcoded secret found - use build args or runtime secrets"
fi

# Check for COPY .env
if grep -qE "COPY.*\.env" "$DOCKERFILE"; then
    print_error "Copying .env file - secrets may be exposed in image layers"
fi

# Check for sudo usage
if grep -q "sudo" "$DOCKERFILE"; then
    print_warning "sudo usage detected - usually unnecessary in containers"
fi

print_header "Best Practices"

# Check for WORKDIR
if grep -q "^WORKDIR " "$DOCKERFILE"; then
    print_ok "WORKDIR is set"
else
    print_warning "No WORKDIR set - using default (/)"
fi

# Check for apt-get update && install pattern
if grep -q "apt-get update" "$DOCKERFILE"; then
    if grep -qE "apt-get update\s*$" "$DOCKERFILE" || grep -qE "apt-get update\s*&&\s*\\" "$DOCKERFILE" | grep -v "install"; then
        # Check if update and install are on separate RUN commands
        UPDATE_COUNT=$(grep -c "apt-get update" "$DOCKERFILE" || true)
        COMBINED=$(grep -cE "apt-get update.*&&.*apt-get install" "$DOCKERFILE" || true)
        if [[ "$UPDATE_COUNT" -gt "$COMBINED" ]]; then
            print_warning "apt-get update should be combined with install in single RUN"
        fi
    fi

    # Check for --no-install-recommends
    if grep -q "apt-get install" "$DOCKERFILE" && ! grep -q "\-\-no-install-recommends" "$DOCKERFILE"; then
        print_warning "Consider using --no-install-recommends with apt-get install"
    fi

    # Check for cleanup
    if ! grep -q "rm -rf /var/lib/apt/lists" "$DOCKERFILE"; then
        print_warning "Consider cleaning apt lists: rm -rf /var/lib/apt/lists/*"
    fi
fi

# Check pip usage
if grep -q "pip install" "$DOCKERFILE"; then
    if ! grep -q "\-\-no-cache-dir" "$DOCKERFILE"; then
        print_warning "Consider using --no-cache-dir with pip install"
    fi
    print_ok "pip install found"
fi

# Check for HEALTHCHECK
if grep -q "^HEALTHCHECK " "$DOCKERFILE"; then
    print_ok "HEALTHCHECK configured"
else
    print_info "No HEALTHCHECK - consider adding for production"
fi

# Check for EXPOSE
if grep -q "^EXPOSE " "$DOCKERFILE"; then
    print_ok "EXPOSE instruction found"
else
    print_info "No EXPOSE instruction"
fi

print_header "Optimization Checks"

# Check for multi-stage build
if grep -c "^FROM " "$DOCKERFILE" | grep -q "[2-9]"; then
    print_ok "Multi-stage build detected"
else
    print_info "Single-stage build - consider multi-stage for production"
fi

# Check for slim/alpine base
if grep -qE "^FROM .+(-slim|-alpine|:alpine|distroless|scratch)" "$DOCKERFILE"; then
    print_ok "Using minimal base image"
else
    print_info "Consider using slim/alpine variant for smaller image"
fi

# Check for layer optimization (COPY before RUN for deps)
FIRST_COPY=$(grep -n "^COPY " "$DOCKERFILE" | head -1 | cut -d: -f1 || echo "999")
DEP_INSTALL=$(grep -nE "(pip install|npm (ci|install)|yarn|go mod download)" "$DOCKERFILE" | head -1 | cut -d: -f1 || echo "0")

if [[ "$DEP_INSTALL" != "0" && "$FIRST_COPY" != "999" ]]; then
    # Check if requirements/package.json is copied before install
    if grep -qE "COPY.*(requirements|package|go\.(mod|sum)|Cargo)" "$DOCKERFILE"; then
        print_ok "Dependency files copied for layer caching"
    fi
fi

# Check .dockerignore
DOCKERIGNORE_PATH=$(dirname "$DOCKERFILE")/.dockerignore
if [[ -f "$DOCKERIGNORE_PATH" ]]; then
    print_ok ".dockerignore exists"

    # Check for common ignores
    if ! grep -q "node_modules" "$DOCKERIGNORE_PATH" 2>/dev/null && grep -q "npm\|yarn\|pnpm" "$DOCKERFILE"; then
        print_warning ".dockerignore should include node_modules"
    fi
    if ! grep -q "__pycache__\|\.pyc" "$DOCKERIGNORE_PATH" 2>/dev/null && grep -q "python\|pip" "$DOCKERFILE"; then
        print_warning ".dockerignore should include __pycache__ and *.pyc"
    fi
    if ! grep -q "\.git" "$DOCKERIGNORE_PATH" 2>/dev/null; then
        print_warning ".dockerignore should include .git"
    fi
else
    print_warning "No .dockerignore found - build context may include unnecessary files"
fi

print_header "Labels & Documentation"

# Check for labels
if grep -q "^LABEL " "$DOCKERFILE"; then
    print_ok "Labels present"
else
    print_info "Consider adding LABEL for image metadata"
fi

# Check for comments
COMMENT_COUNT=$(grep -c "^#" "$DOCKERFILE" || true)
if [[ "$COMMENT_COUNT" -gt 2 ]]; then
    print_ok "Dockerfile has comments"
else
    print_info "Consider adding comments to explain complex steps"
fi

print_header "Summary"

echo ""
if [[ $ERRORS -eq 0 && $WARNINGS -eq 0 ]]; then
    echo -e "${GREEN}No issues found!${NC}"
elif [[ $ERRORS -eq 0 ]]; then
    echo -e "${YELLOW}$WARNINGS warning(s), 0 errors${NC}"
else
    echo -e "${RED}$ERRORS error(s), $WARNINGS warning(s)${NC}"
fi

echo ""

# Exit with error code if there are errors
if [[ $ERRORS -gt 0 ]]; then
    exit 1
fi

exit 0
