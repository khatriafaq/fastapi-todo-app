# Docker Image Optimization Guide

Techniques for reducing image size, improving build speed, and optimizing layer caching.

---

## Layer Caching Fundamentals

### How Docker Caching Works
- Docker caches each layer based on the instruction and file contents
- If a layer changes, all subsequent layers are rebuilt
- Order matters: put stable layers first, changing layers last

### Optimal Layer Order

```dockerfile
# 1. Base image (changes rarely)
FROM python:3.12-slim

# 2. System dependencies (changes rarely)
RUN apt-get update && apt-get install -y --no-install-recommends \
    libpq-dev \
    && rm -rf /var/lib/apt/lists/*

# 3. Dependency files (changes occasionally)
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# 4. Application code (changes frequently)
COPY . .
```

### Cache-Busting Scenarios

```dockerfile
# BAD: Copying everything first invalidates cache
COPY . .
RUN pip install -r requirements.txt

# GOOD: Copy dependency file first
COPY requirements.txt .
RUN pip install -r requirements.txt
COPY . .
```

---

## Multi-Stage Builds

### Basic Pattern

```dockerfile
# Stage 1: Build (includes compilers, dev deps)
FROM python:3.12 AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt
COPY . .

# Stage 2: Runtime (minimal, no build tools)
FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY --from=builder /app .
ENV PATH=/root/.local/bin:$PATH
CMD ["python", "main.py"]
```

### Named Stages for Complex Builds

```dockerfile
FROM node:20 AS deps
WORKDIR /app
COPY package*.json ./
RUN npm ci

FROM deps AS builder
COPY . .
RUN npm run build

FROM deps AS tester
COPY . .
RUN npm test

FROM node:20-slim AS runner
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=deps /app/node_modules ./node_modules
CMD ["node", "dist/index.js"]
```

Build specific stage:
```bash
docker build --target tester -t myapp:test .
```

---

## BuildKit Features

Enable BuildKit:
```bash
export DOCKER_BUILDKIT=1
# or
docker buildx build .
```

### Cache Mounts

```dockerfile
# syntax=docker/dockerfile:1.4

# Cache pip downloads between builds
RUN --mount=type=cache,target=/root/.cache/pip \
    pip install -r requirements.txt

# Cache npm modules
RUN --mount=type=cache,target=/root/.npm \
    npm ci

# Cache go modules
RUN --mount=type=cache,target=/go/pkg/mod \
    go mod download
```

### Parallel Builds

```dockerfile
# syntax=docker/dockerfile:1.4

FROM alpine AS stage1
RUN sleep 5 && echo "stage1" > /stage1

FROM alpine AS stage2
RUN sleep 5 && echo "stage2" > /stage2

FROM alpine
COPY --from=stage1 /stage1 .
COPY --from=stage2 /stage2 .
# Both stages build in parallel!
```

### Secrets Mount

```dockerfile
# syntax=docker/dockerfile:1.4

RUN --mount=type=secret,id=npmrc,target=/root/.npmrc \
    npm ci
```

---

## Image Size Reduction

### Base Image Selection

| Choice | Size Impact | Notes |
|--------|-------------|-------|
| `scratch` | Smallest | Only for static binaries |
| `distroless` | ~2-20 MB | No shell, minimal |
| `alpine` | ~5 MB | musl libc, may have compatibility issues |
| `*-slim` | ~50-150 MB | Good balance |
| Standard | ~300+ MB | Full tooling |

### Remove Unnecessary Files

```dockerfile
# Clean up in the same layer
RUN apt-get update \
    && apt-get install -y --no-install-recommends pkg \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && rm -rf /tmp/*

# Don't install documentation
RUN pip install --no-cache-dir package

# Remove test files in Python packages
RUN find /usr/local -name "*.pyc" -delete \
    && find /usr/local -name "__pycache__" -delete \
    && find /usr/local -name "tests" -type d -exec rm -rf {} + 2>/dev/null || true
```

### .dockerignore

Essential `.dockerignore`:
```
.git
.gitignore
Dockerfile*
docker-compose*
.docker
node_modules
__pycache__
*.pyc
.venv
venv
.env
.env.*
!.env.example
*.md
docs
.vscode
.idea
coverage
.coverage
htmlcov
.pytest_cache
dist
build
*.egg-info
.github
```

---

## Build Speed Optimization

### Dependency Caching

**Python with BuildKit cache:**
```dockerfile
# syntax=docker/dockerfile:1.4
FROM python:3.12-slim

RUN --mount=type=cache,target=/root/.cache/pip \
    --mount=type=bind,source=requirements.txt,target=requirements.txt \
    pip install -r requirements.txt
```

**Node.js with npm cache:**
```dockerfile
# syntax=docker/dockerfile:1.4
FROM node:20

RUN --mount=type=cache,target=/root/.npm \
    --mount=type=bind,source=package.json,target=package.json \
    --mount=type=bind,source=package-lock.json,target=package-lock.json \
    npm ci
```

### Parallel Downloads

```dockerfile
# Go: parallel module downloads
ENV GOPROXY=https://proxy.golang.org,direct

# Python: parallel pip installs (default in recent pip)
RUN pip install --no-cache-dir -r requirements.txt
```

### Minimize Context Size

```bash
# Check context size before build
du -sh . --exclude=.git

# Build with specific context
docker build -f Dockerfile ./src
```

---

## Optimization Checklist

### Image Size
- [ ] Using slim/alpine base image
- [ ] Multi-stage build implemented
- [ ] No unnecessary packages installed
- [ ] Build tools excluded from final image
- [ ] Cache directories cleaned
- [ ] .dockerignore is comprehensive

### Build Speed
- [ ] Dependencies copied before source code
- [ ] BuildKit enabled
- [ ] Cache mounts for package managers
- [ ] Parallel stages where possible
- [ ] Context size minimized

### Layer Efficiency
- [ ] Related commands combined in single RUN
- [ ] Cleanup in same layer as install
- [ ] Stable layers before changing layers
- [ ] No unnecessary COPY instructions

---

## Measuring Image Size

```bash
# View image size
docker images myapp

# Detailed layer information
docker history myapp:latest

# Dive tool for layer analysis
dive myapp:latest

# Compare compressed sizes
docker save myapp:latest | gzip | wc -c
```

---

## Before/After Examples

### Python App

**Before (850 MB):**
```dockerfile
FROM python:3.12
WORKDIR /app
COPY . .
RUN pip install -r requirements.txt
CMD ["python", "main.py"]
```

**After (120 MB):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app
COPY --from=builder /root/.local /root/.local
COPY . .
ENV PATH=/root/.local/bin:$PATH
CMD ["python", "main.py"]
```

### Node.js App

**Before (950 MB):**
```dockerfile
FROM node:20
WORKDIR /app
COPY . .
RUN npm install
CMD ["node", "index.js"]
```

**After (180 MB):**
```dockerfile
FROM node:20-slim AS builder
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build

FROM node:20-slim
WORKDIR /app
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/node_modules ./node_modules
ENV NODE_ENV=production
CMD ["node", "dist/index.js"]
```

### Go App

**Before (800 MB):**
```dockerfile
FROM golang:1.22
WORKDIR /app
COPY . .
RUN go build -o server .
CMD ["./server"]
```

**After (12 MB with distroless, 0 MB base with scratch):**
```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o server .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /app/server /server
USER nonroot:nonroot
CMD ["/server"]
```
