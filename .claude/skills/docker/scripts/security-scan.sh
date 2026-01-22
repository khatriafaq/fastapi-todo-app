#!/bin/bash
#
# Docker Security Scanner
# Performs basic security checks on Dockerfiles
# For comprehensive scanning, use Trivy or Docker Scout
#
# Usage: ./security-scan.sh <path-to-dockerfile>

set -e

DOCKERFILE="${1:-Dockerfile}"
CRITICAL=0
HIGH=0
MEDIUM=0
LOW=0

# Colors for output
RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

print_header() {
    echo -e "\n${BLUE}=== $1 ===${NC}\n"
}

print_critical() {
    echo -e "${RED}[CRITICAL]${NC} $1"
    ((CRITICAL++))
}

print_high() {
    echo -e "${RED}[HIGH]${NC} $1"
    ((HIGH++))
}

print_medium() {
    echo -e "${YELLOW}[MEDIUM]${NC} $1"
    ((MEDIUM++))
}

print_low() {
    echo -e "${MAGENTA}[LOW]${NC} $1"
    ((LOW++))
}

print_ok() {
    echo -e "${GREEN}[PASS]${NC} $1"
}

# Check if file exists
if [[ ! -f "$DOCKERFILE" ]]; then
    echo -e "${RED}Error: Dockerfile not found at '$DOCKERFILE'${NC}"
    exit 1
fi

echo -e "${BLUE}Security Scan: $DOCKERFILE${NC}"
echo "=========================================="

print_header "CIS Docker Benchmark Checks"

# 4.1: Ensure that a user for the container has been created
if grep -q "^USER " "$DOCKERFILE"; then
    USER_LINE=$(grep "^USER " "$DOCKERFILE" | tail -1)
    if echo "$USER_LINE" | grep -qE "USER (root|0)\b"; then
        print_high "4.1 Container explicitly runs as root"
    else
        print_ok "4.1 Non-root user configured"
    fi
else
    print_high "4.1 No USER instruction - container runs as root by default"
fi

# 4.2: Ensure that containers use trusted base images
BASE_IMAGE=$(grep "^FROM " "$DOCKERFILE" | head -1 | awk '{print $2}')
if echo "$BASE_IMAGE" | grep -qE "^(python|node|golang|ruby|openjdk|eclipse-temurin|nginx|alpine|debian|ubuntu|postgres|redis|mongo):"; then
    print_ok "4.2 Using official base image: $BASE_IMAGE"
elif echo "$BASE_IMAGE" | grep -qE "^(gcr\.io/distroless|scratch)"; then
    print_ok "4.2 Using minimal/distroless base image"
else
    print_medium "4.2 Verify base image source: $BASE_IMAGE"
fi

# 4.3: Ensure unnecessary packages are not installed
if grep -q "apt-get install" "$DOCKERFILE"; then
    if grep -qE "install.*(vim|nano|curl|wget|ssh|telnet|ftp)" "$DOCKERFILE"; then
        PACKAGES=$(grep -oE "(vim|nano|curl|wget|ssh|telnet|ftp)" "$DOCKERFILE" | sort -u | tr '\n' ' ')
        print_low "4.3 Potentially unnecessary packages: $PACKAGES"
    else
        print_ok "4.3 No obviously unnecessary packages detected"
    fi
fi

# 4.6: Ensure HEALTHCHECK instructions have been added
if grep -q "^HEALTHCHECK " "$DOCKERFILE"; then
    print_ok "4.6 HEALTHCHECK instruction present"
else
    print_low "4.6 No HEALTHCHECK instruction"
fi

# 4.7: Ensure update instructions are not used alone
if grep -qE "apt-get update\s*$" "$DOCKERFILE" 2>/dev/null; then
    print_medium "4.7 apt-get update on its own line (cache may be stale)"
fi

# 4.9: Ensure COPY is used instead of ADD
if grep -q "^ADD " "$DOCKERFILE"; then
    if grep -qE "^ADD .*(https?://|\.tar|\.gz|\.zip)" "$DOCKERFILE"; then
        print_low "4.9 ADD used for archive/URL (intentional, but verify)"
    else
        print_medium "4.9 Prefer COPY over ADD for local files"
    fi
else
    print_ok "4.9 COPY used instead of ADD"
fi

print_header "Secrets Detection"

# Check for hardcoded passwords/secrets
SECRETS_FOUND=false

# ENV with sensitive keywords
if grep -qiE "^ENV.*(PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL|AUTH).*=" "$DOCKERFILE"; then
    print_critical "Hardcoded secret in ENV instruction"
    SECRETS_FOUND=true
fi

# ARG with sensitive keywords (and default value)
if grep -qiE "^ARG.*(PASSWORD|SECRET|KEY|TOKEN|CREDENTIAL).*=" "$DOCKERFILE"; then
    print_critical "Hardcoded secret in ARG instruction"
    SECRETS_FOUND=true
fi

# COPY .env file
if grep -qE "^COPY.*\.env" "$DOCKERFILE"; then
    print_critical "Copying .env file - secrets exposed in image layer"
    SECRETS_FOUND=true
fi

# Common secret file patterns
if grep -qE "COPY.*(credentials|secrets|\.pem|\.key|id_rsa)" "$DOCKERFILE"; then
    print_high "Copying potential secret/key file"
    SECRETS_FOUND=true
fi

# AWS credentials
if grep -qE "AWS_(ACCESS_KEY|SECRET)" "$DOCKERFILE"; then
    print_critical "AWS credentials referenced in Dockerfile"
    SECRETS_FOUND=true
fi

if [[ "$SECRETS_FOUND" == "false" ]]; then
    print_ok "No obvious hardcoded secrets detected"
fi

print_header "Base Image Security"

# Check for :latest tag
if grep -qE "^FROM .+:latest" "$DOCKERFILE"; then
    print_high "Using :latest tag - unpredictable, may include vulnerabilities"
elif grep -qE "^FROM [^:@]+$" "$DOCKERFILE"; then
    print_high "No tag specified (defaults to :latest)"
else
    # Check if using SHA digest
    if grep -qE "^FROM .+@sha256:" "$DOCKERFILE"; then
        print_ok "Using immutable SHA digest (most secure)"
    else
        print_ok "Using specific version tag"
    fi
fi

# Check for known vulnerable base images (outdated)
if grep -qE "FROM.*(python:2|python:3\.[0-7][^0-9]|node:1[0-6][^0-9]|node:[0-9][^0-9])" "$DOCKERFILE"; then
    print_high "Using outdated/EOL base image version"
fi

print_header "Privilege Escalation Risks"

# Check for setuid/setgid binaries being added
if grep -qE "chmod.*(4|2)[0-7]{3}|chmod.*[+]s" "$DOCKERFILE"; then
    print_high "Setting setuid/setgid bits - potential privilege escalation"
fi

# Check for sudo installation
if grep -qE "apt-get install.*sudo|apk add.*sudo" "$DOCKERFILE"; then
    print_medium "Installing sudo - usually unnecessary in containers"
fi

# Check for capability-related commands
if grep -qE "setcap|getcap" "$DOCKERFILE"; then
    print_medium "Capability manipulation detected - verify necessity"
fi

print_header "Network Security"

# Check for privileged ports
EXPOSED_PORTS=$(grep -E "^EXPOSE " "$DOCKERFILE" | grep -oE "[0-9]+" || true)
for port in $EXPOSED_PORTS; do
    if [[ "$port" -lt 1024 ]]; then
        print_low "Exposing privileged port $port (requires root or capabilities)"
    fi
done

# Check for SSH server
if grep -qE "sshd|openssh-server" "$DOCKERFILE"; then
    print_medium "SSH server in container - usually an anti-pattern"
fi

print_header "Recommendations"

# Multi-stage build check
if ! grep -c "^FROM " "$DOCKERFILE" | grep -q "[2-9]"; then
    echo -e "${BLUE}[TIP]${NC} Consider multi-stage build to exclude build tools from final image"
fi

# Minimal base image check
if ! grep -qE "^FROM .+(-slim|-alpine|distroless|scratch)" "$DOCKERFILE"; then
    echo -e "${BLUE}[TIP]${NC} Consider using slim/alpine/distroless base for smaller attack surface"
fi

# Scan with external tools
echo -e "\n${BLUE}[TIP]${NC} For comprehensive vulnerability scanning, use:"
echo "  - trivy image <image-name>"
echo "  - docker scout quickview <image-name>"
echo "  - snyk container test <image-name>"

print_header "Summary"

echo ""
TOTAL=$((CRITICAL + HIGH + MEDIUM + LOW))
if [[ $TOTAL -eq 0 ]]; then
    echo -e "${GREEN}No security issues found!${NC}"
else
    echo -e "Found: ${RED}$CRITICAL critical${NC}, ${RED}$HIGH high${NC}, ${YELLOW}$MEDIUM medium${NC}, ${MAGENTA}$LOW low${NC}"
fi

echo ""

# Exit codes based on severity
if [[ $CRITICAL -gt 0 ]]; then
    exit 2
elif [[ $HIGH -gt 0 ]]; then
    exit 1
fi

exit 0
