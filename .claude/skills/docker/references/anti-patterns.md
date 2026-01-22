# Docker Anti-Patterns

Common mistakes to avoid when writing Dockerfiles and working with containers.

---

## Security Anti-Patterns

### Running as Root

**Problem:**
```dockerfile
# Implicit root user - security vulnerability
FROM python:3.12-slim
WORKDIR /app
COPY . .
CMD ["python", "main.py"]
```

**Solution:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app
RUN useradd --create-home --uid 1000 appuser
COPY --chown=appuser:appuser . .
USER appuser
CMD ["python", "main.py"]
```

### Hardcoded Secrets

**Problem:**
```dockerfile
# Secrets visible in image layers!
ENV DATABASE_PASSWORD=super_secret_123
ARG API_KEY=sk-abc123
COPY .env /app/
```

**Solution:**
```dockerfile
# Pass at runtime
# docker run -e DATABASE_PASSWORD=xxx myapp

# Or use BuildKit secrets for build-time
# syntax=docker/dockerfile:1.4
RUN --mount=type=secret,id=api_key \
    API_KEY=$(cat /run/secrets/api_key) ./build.sh
```

### Using :latest Tag

**Problem:**
```dockerfile
# Unpredictable - different results over time
FROM python:latest
FROM node:latest
```

**Solution:**
```dockerfile
# Pin specific versions
FROM python:3.12-slim
FROM node:20.10-slim

# Even better - use SHA digest for immutability
FROM python:3.12-slim@sha256:abc123...
```

---

## Build Anti-Patterns

### Installing Unnecessary Packages

**Problem:**
```dockerfile
# Installs recommended packages, increasing size and attack surface
RUN apt-get update && apt-get install -y curl git vim nano wget
```

**Solution:**
```dockerfile
# Only install what you need, skip recommends
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    && rm -rf /var/lib/apt/lists/*
```

### Separate apt-get update and install

**Problem:**
```dockerfile
# Cached update may be stale
RUN apt-get update
RUN apt-get install -y package
```

**Solution:**
```dockerfile
# Combine in single layer
RUN apt-get update && apt-get install -y --no-install-recommends \
    package \
    && rm -rf /var/lib/apt/lists/*
```

### Not Cleaning Up in Same Layer

**Problem:**
```dockerfile
# Cache not removed - increases layer size
RUN apt-get update && apt-get install -y package
RUN rm -rf /var/lib/apt/lists/*
```

**Solution:**
```dockerfile
# Clean up in same RUN instruction
RUN apt-get update \
    && apt-get install -y --no-install-recommends package \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*
```

### Copying Everything Before Installing Dependencies

**Problem:**
```dockerfile
# Any code change invalidates dependency cache
COPY . .
RUN pip install -r requirements.txt
```

**Solution:**
```dockerfile
# Copy dependency file first for better caching
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

---

## Image Size Anti-Patterns

### Using Full Base Image

**Problem:**
```dockerfile
# 900+ MB base image
FROM python:3.12
FROM node:20
FROM golang:1.22
```

**Solution:**
```dockerfile
# Use slim or alpine variants
FROM python:3.12-slim    # ~120 MB
FROM node:20-slim        # ~180 MB
FROM golang:1.22-alpine  # ~250 MB (for builds)
```

### Not Using Multi-Stage Builds

**Problem:**
```dockerfile
# Build tools included in final image
FROM python:3.12
RUN apt-get update && apt-get install -y build-essential
COPY . .
RUN pip install -r requirements.txt
CMD ["python", "main.py"]
```

**Solution:**
```dockerfile
# Multi-stage: build tools only in builder
FROM python:3.12 AS builder
RUN apt-get update && apt-get install -y build-essential
COPY requirements.txt .
RUN pip install --user -r requirements.txt

FROM python:3.12-slim
COPY --from=builder /root/.local /root/.local
COPY . .
CMD ["python", "main.py"]
```

### Missing .dockerignore

**Problem:**
```dockerfile
# Copies unnecessary files: .git, node_modules, __pycache__, etc.
COPY . .
```

**Solution:**
Create `.dockerignore`:
```
.git
node_modules
__pycache__
*.pyc
.venv
.env
*.md
.vscode
```

---

## Runtime Anti-Patterns

### Storing Data in Container

**Problem:**
```dockerfile
# Data lost when container is removed
VOLUME /data  # Implicit, not managed
```

**Solution:**
```bash
# Use explicit named volumes
docker run -v mydata:/data myapp

# Or bind mounts for development
docker run -v ./data:/data myapp
```

### Multiple Processes in One Container

**Problem:**
```dockerfile
# Runs multiple services - hard to scale and manage
CMD ["sh", "-c", "nginx & python app.py"]
```

**Solution:**
Use separate containers:
```yaml
# docker-compose.yml
services:
  web:
    image: nginx
  app:
    image: myapp
```

### Using ENTRYPOINT for Everything

**Problem:**
```dockerfile
# Can't easily override command
ENTRYPOINT ["python", "main.py"]
```

**Solution:**
```dockerfile
# ENTRYPOINT for the executable, CMD for default arguments
ENTRYPOINT ["python"]
CMD ["main.py"]

# Or just CMD for flexibility
CMD ["python", "main.py"]
```

---

## Networking Anti-Patterns

### Hardcoded Ports

**Problem:**
```dockerfile
# Port hardcoded in multiple places
EXPOSE 3000
ENV PORT=3000
CMD ["node", "server.js", "--port", "3000"]
```

**Solution:**
```dockerfile
# Use environment variable
ARG PORT=3000
ENV PORT=${PORT}
EXPOSE ${PORT}
CMD ["node", "server.js"]
```

### Using localhost in Container

**Problem:**
```python
# Won't be accessible from outside container
app.run(host='localhost', port=8000)
```

**Solution:**
```python
# Bind to all interfaces
app.run(host='0.0.0.0', port=8000)
```

---

## Development Anti-Patterns

### No Health Check

**Problem:**
```dockerfile
# No way to verify container health
CMD ["python", "main.py"]
```

**Solution:**
```dockerfile
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1
CMD ["python", "main.py"]
```

### Ignoring Build Arguments

**Problem:**
```dockerfile
# Hardcoded values, can't customize without editing
FROM python:3.12
ENV NODE_ENV=production
```

**Solution:**
```dockerfile
ARG PYTHON_VERSION=3.12
FROM python:${PYTHON_VERSION}

ARG NODE_ENV=production
ENV NODE_ENV=${NODE_ENV}
```

Build with:
```bash
docker build --build-arg PYTHON_VERSION=3.11 --build-arg NODE_ENV=development .
```

---

## Quick Reference: Anti-Pattern Fixes

| Anti-Pattern | Fix |
|--------------|-----|
| Running as root | Add `USER 1000` or named user |
| `:latest` tag | Pin specific version |
| Hardcoded secrets | Use runtime env vars or BuildKit secrets |
| apt-get update alone | Combine with install in one RUN |
| Full base image | Use `-slim` or `-alpine` variant |
| No .dockerignore | Create comprehensive .dockerignore |
| COPY . before deps | Copy dependency files first |
| No multi-stage | Separate builder and runtime stages |
| No health check | Add HEALTHCHECK instruction |
| localhost binding | Use 0.0.0.0 |
