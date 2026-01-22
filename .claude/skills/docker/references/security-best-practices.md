# Docker Security Best Practices

Comprehensive security hardening guide for Docker containers.

---

## Non-Root Users

### Why It Matters
Running containers as root exposes the host system if the container is compromised. Always run production containers as non-root.

### Implementation Patterns

**Debian/Ubuntu based images:**
```dockerfile
# Create user with specific UID
RUN useradd --create-home --uid 1000 appuser

# Set ownership of app directory
COPY --chown=appuser:appuser . /app

# Switch to non-root user (do this last)
USER appuser
```

**Alpine based images:**
```dockerfile
# Alpine uses adduser instead of useradd
RUN adduser -D -u 1000 appuser

COPY --chown=appuser:appuser . /app
USER appuser
```

**Distroless images:**
```dockerfile
# Distroless has a built-in nonroot user
FROM gcr.io/distroless/static:nonroot
USER nonroot:nonroot
```

**Using numeric UID (recommended for k8s):**
```dockerfile
# Use numeric UID instead of username for better compatibility
USER 1000
```

---

## Secrets Management

### What NOT to Do

```dockerfile
# NEVER do this - secrets visible in image layers
ENV DATABASE_PASSWORD=secret123
ARG API_KEY=abc123

# NEVER do this - secrets in build history
COPY .env /app/
```

### Build-time Secrets (BuildKit)

```dockerfile
# syntax=docker/dockerfile:1.4

# Mount secret during build (not stored in image)
RUN --mount=type=secret,id=npm_token \
    NPM_TOKEN=$(cat /run/secrets/npm_token) npm ci
```

Build with:
```bash
docker build --secret id=npm_token,src=.npm_token .
```

### Runtime Secrets

**Using environment variables (acceptable for non-sensitive config):**
```bash
docker run -e DATABASE_URL=postgres://... myapp
```

**Using Docker secrets (Swarm/Compose):**
```yaml
# docker-compose.yml
services:
  app:
    secrets:
      - db_password
secrets:
  db_password:
    file: ./secrets/db_password.txt
```

**Using mounted files:**
```bash
docker run -v /path/to/secrets:/run/secrets:ro myapp
```

---

## Minimal Base Images

### Image Comparison

| Image | Size | Shell | Package Manager | Use Case |
|-------|------|-------|-----------------|----------|
| `scratch` | 0 MB | No | No | Static Go/Rust binaries |
| `distroless` | ~2 MB | No | No | Production workloads |
| `alpine` | ~5 MB | Yes | apk | When shell needed |
| `*-slim` | ~50-150 MB | Yes | apt | Most applications |
| `standard` | ~300+ MB | Yes | apt | Development/debugging |

### Recommendations by Use Case

**Minimal attack surface (Go, Rust):**
```dockerfile
FROM scratch
# or
FROM gcr.io/distroless/static:nonroot
```

**Need shell but want small size:**
```dockerfile
FROM alpine:3.19
```

**Need glibc compatibility:**
```dockerfile
FROM debian:bookworm-slim
# or
FROM python:3.12-slim  # language-specific slim
```

---

## Package Installation Security

### Debian/Ubuntu

```dockerfile
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        package1 \
        package2 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

Key flags:
- `--no-install-recommends`: Skip suggested packages
- `apt-get clean`: Clean package cache
- `rm -rf /var/lib/apt/lists/*`: Remove package lists

### Alpine

```dockerfile
RUN apk add --no-cache \
    package1 \
    package2
```

Key flags:
- `--no-cache`: Don't cache package index locally

---

## Image Scanning

### Trivy (Recommended)

**Scan an image:**
```bash
trivy image myapp:latest
```

**Scan with severity filter:**
```bash
trivy image --severity HIGH,CRITICAL myapp:latest
```

**Fail on vulnerabilities (CI/CD):**
```bash
trivy image --exit-code 1 --severity CRITICAL myapp:latest
```

**Scan Dockerfile:**
```bash
trivy config Dockerfile
```

### Docker Scout

```bash
# Enable Docker Scout
docker scout quickview myapp:latest

# Get recommendations
docker scout recommendations myapp:latest
```

### GitHub Actions Integration

```yaml
- name: Run Trivy vulnerability scanner
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: ${{ env.REGISTRY }}/${{ env.IMAGE_NAME }}:${{ github.sha }}
    format: 'sarif'
    output: 'trivy-results.sarif'
    severity: 'CRITICAL,HIGH'

- name: Upload Trivy scan results
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

---

## Read-Only Filesystem

```dockerfile
# In Dockerfile, ensure app doesn't need to write to filesystem

# At runtime
docker run --read-only myapp

# With tmpfs for temporary files
docker run --read-only --tmpfs /tmp myapp
```

---

## Drop Capabilities

```bash
# Drop all capabilities and add only what's needed
docker run --cap-drop=ALL --cap-add=NET_BIND_SERVICE myapp
```

Common capabilities to consider:
- `NET_BIND_SERVICE`: Bind to ports below 1024
- `CHOWN`: Change file ownership
- `SETUID`/`SETGID`: Change process UID/GID

---

## No New Privileges

```bash
docker run --security-opt=no-new-privileges:true myapp
```

This prevents the container from gaining additional privileges via setuid binaries.

---

## Network Security

### Use Non-Root Ports

```dockerfile
# Use ports above 1024 (don't need root)
EXPOSE 8080  # Instead of 80
EXPOSE 8443  # Instead of 443
```

### Limit Network Access

```bash
# Disable network entirely for processing jobs
docker run --network=none myapp

# Use internal networks
docker network create --internal internal-net
```

---

## Security Checklist

### Dockerfile
- [ ] Using specific base image tag (not `:latest`)
- [ ] Non-root user configured
- [ ] No secrets in ENV, ARG, or COPY
- [ ] Minimal packages installed
- [ ] Multi-stage build to exclude build tools
- [ ] No unnecessary SUID/SGID binaries

### Runtime
- [ ] Read-only filesystem where possible
- [ ] Dropped unnecessary capabilities
- [ ] Resource limits configured
- [ ] No privileged mode
- [ ] Health checks configured

### CI/CD
- [ ] Image scanning in pipeline
- [ ] Signed images
- [ ] Base image update automation
- [ ] Security policy enforcement

---

## Security Headers for Health Checks

If your health check endpoint is exposed, ensure it doesn't leak sensitive information:

```python
# FastAPI example
@app.get("/health")
async def health_check():
    return {"status": "healthy"}
    # Don't include: version, environment, internal IPs, etc.
```

---

## Secure Dockerfile Template

```dockerfile
# syntax=docker/dockerfile:1.4
FROM python:3.12-slim AS builder
WORKDIR /app

# Install dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app

# Security: Create non-root user
RUN useradd --create-home --uid 1000 appuser

# Copy only necessary files
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . .

# Security: Environment configuration
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Security: Run as non-root
USER appuser

# Security: Document port (use non-privileged)
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```
