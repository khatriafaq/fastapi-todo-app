# Docker Skill

A production-ready Docker skill that teaches containerization progressively, supporting multiple languages (Python, Node.js, Go) with security best practices and CI/CD integration.

---

## What This Skill Does

- Creates Dockerfiles for various languages and frameworks
- Implements multi-stage builds for optimized images
- Applies security best practices (non-root users, minimal images)
- Sets up development environments with hot reload
- Integrates with CI/CD pipelines and container registries
- Creates Docker Compose configurations for local development
- Provides troubleshooting guidance for common Docker issues

## What This Skill Does NOT Do

- Manage Kubernetes deployments (use a dedicated k8s skill)
- Handle container orchestration beyond Docker Compose
- Configure cloud-specific container services (ECS, Cloud Run, AKS)
- Set up Docker Swarm clusters
- Manage container networking at scale

---

## Before Implementation

Before generating any Dockerfile, gather this context:

### Required Information
1. **Language/Runtime**: Python, Node.js, Go, Rust, Java, etc.
2. **Package Manager**: pip/poetry/uv, npm/yarn/pnpm, go modules
3. **Entry Point**: How the application starts
4. **Port(s)**: What ports need to be exposed

### Determine Complexity Level
Ask or infer the user's needs:

| Level | Indicators | Output |
|-------|-----------|--------|
| **1. First Dockerfile** | "containerize", "first Docker", "getting started", beginner | Single-stage, educational comments, basic instructions |
| **2. Development Setup** | "development", "hot reload", "local", "dev environment" | Volume mounts, dev dependencies, docker-compose |
| **3. Optimized Build** | "optimize", "smaller", "multi-stage", "size" | Multi-stage builds, minimal images, .dockerignore |
| **4. Production-Ready** | "production", "deploy", "secure", "hardened" | Security hardening, health checks, non-root user |
| **5. CI/CD Integration** | "pipeline", "registry", "automated", "GitHub Actions" | CI workflows, registry push, automated scanning |

### Scan Existing Project
```bash
# Check for existing Docker files
ls -la Dockerfile* docker-compose* .dockerignore 2>/dev/null

# Identify package manager
ls package.json requirements.txt pyproject.toml go.mod Cargo.toml pom.xml 2>/dev/null

# Check for existing CI/CD
ls -la .github/workflows/ .gitlab-ci.yml 2>/dev/null
```

---

## Implementation Workflow

### Step 1: Assess Project

```
1. Identify language and package manager
2. Determine entry point and ports
3. Check for existing Docker configuration
4. Identify complexity level needed
```

### Step 2: Generate Dockerfile

Based on complexity level, generate appropriate Dockerfile:

**Level 1-2**: Use single-stage with educational comments
**Level 3-5**: Use multi-stage builds with optimization

### Step 3: Create Supporting Files

- `.dockerignore` - Exclude unnecessary files
- `docker-compose.yml` - For local development (levels 2+)
- `.github/workflows/docker.yml` - For CI/CD (level 5)

### Step 4: Validate

Run the analyze script and security checks:
```bash
./scripts/analyze-dockerfile.sh Dockerfile
./scripts/security-scan.sh Dockerfile
```

---

## Language Quick Reference

### Python
- **Base Images**: `python:3.12-slim` (recommended), `python:3.12-alpine` (smaller but compatibility issues)
- **Package Managers**: pip, poetry, uv
- **Key Pattern**: Install dependencies first for layer caching
- **Reference**: [dockerfile-patterns.md](references/dockerfile-patterns.md#python)

### Node.js
- **Base Images**: `node:20-slim` (recommended), `node:20-alpine`
- **Package Managers**: npm, yarn, pnpm
- **Key Pattern**: Use `npm ci` for reproducible builds
- **Reference**: [dockerfile-patterns.md](references/dockerfile-patterns.md#nodejs)

### Go
- **Base Images**: `golang:1.22` for build, `scratch` or `gcr.io/distroless/static` for runtime
- **Key Pattern**: Static binary compilation, minimal runtime image
- **Reference**: [dockerfile-patterns.md](references/dockerfile-patterns.md#go)

---

## Decision Trees

### Base Image Selection

```
Is minimal size critical?
├── Yes: Does app need glibc?
│   ├── Yes: Use -slim variant (debian-based)
│   └── No: Use -alpine variant (musl-based)
└── No: Use standard image for easier debugging
```

### Single vs Multi-Stage

```
What's the priority?
├── Learning/Simplicity → Single-stage with comments
├── Image Size → Multi-stage (builder + runtime)
├── Build Speed → Multi-stage with BuildKit cache
└── Security → Multi-stage with distroless/scratch
```

### Development vs Production

```
Environment?
├── Development:
│   ├── Include dev dependencies
│   ├── Mount source as volume
│   ├── Enable hot reload
│   └── Use docker-compose
└── Production:
    ├── Exclude dev dependencies
    ├── Copy only built artifacts
    ├── Run as non-root user
    └── Add health checks
```

---

## Common Patterns

### Multi-Stage Build Template

```dockerfile
# Stage 1: Build
FROM <language>:<version>-slim AS builder
WORKDIR /app

# Install dependencies first (layer caching)
COPY <dependency-file> .
RUN <install-command>

# Copy source and build
COPY . .
RUN <build-command>

# Stage 2: Runtime
FROM <language>:<version>-slim
WORKDIR /app

# Create non-root user
RUN useradd --create-home --uid 1000 appuser

# Copy only what's needed from builder
COPY --from=builder /app/<artifacts> .

# Security: run as non-root
USER appuser

# Expose port and set entrypoint
EXPOSE <port>
CMD ["<command>"]
```

### Non-Root User Pattern

```dockerfile
# Create user with specific UID (1000 is common)
RUN useradd --create-home --uid 1000 appuser

# For Alpine images
RUN adduser -D -u 1000 appuser

# Set ownership of app directory
COPY --chown=appuser:appuser . /app

# Switch to non-root user
USER appuser
```

### Health Check Pattern

```dockerfile
# HTTP health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# For images without curl
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --no-verbose --tries=1 --spider http://localhost:8000/health || exit 1

# TCP port check (no HTTP endpoint)
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD nc -z localhost 8000 || exit 1
```

### .dockerignore Template

```
# Git
.git
.gitignore

# Docker
Dockerfile*
docker-compose*
.docker

# Dependencies (will be installed in container)
node_modules
__pycache__
*.pyc
.venv
venv

# IDE
.vscode
.idea
*.swp
*.swo

# Testing
coverage
.coverage
htmlcov
.pytest_cache

# Build artifacts
dist
build
*.egg-info

# Environment files (contain secrets)
.env
.env.*
!.env.example

# Documentation
*.md
docs

# CI/CD
.github
.gitlab-ci.yml
```

### Labels for Metadata

```dockerfile
LABEL org.opencontainers.image.title="My App" \
      org.opencontainers.image.description="Application description" \
      org.opencontainers.image.version="1.0.0" \
      org.opencontainers.image.source="https://github.com/user/repo" \
      org.opencontainers.image.licenses="MIT"
```

---

## Anti-Patterns Summary

| Anti-Pattern | Problem | Solution |
|--------------|---------|----------|
| Running as root | Security vulnerability | Add `USER 1000` or named user |
| Using `:latest` tag | Unpredictable builds | Pin specific versions |
| Hardcoded secrets | Security breach risk | Use build args or secrets mount |
| Installing unnecessary packages | Larger image, more vulnerabilities | Use `--no-install-recommends` |
| Not using .dockerignore | Large context, slow builds | Create comprehensive .dockerignore |
| Single `RUN apt-get` | Stale package cache | Combine update and install |
| Copying entire context first | Cache invalidation | Copy dependency files first |

**Full details**: [anti-patterns.md](references/anti-patterns.md)

---

## Quick Reference Table

| Topic | Reference File |
|-------|---------------|
| Language-specific Dockerfiles | [dockerfile-patterns.md](references/dockerfile-patterns.md) |
| Image optimization | [optimization-guide.md](references/optimization-guide.md) |
| Security hardening | [security-best-practices.md](references/security-best-practices.md) |
| CI/CD integration | [registry-workflows.md](references/registry-workflows.md) |
| Docker Compose patterns | [compose-patterns.md](references/compose-patterns.md) |
| Troubleshooting | [troubleshooting.md](references/troubleshooting.md) |
| What NOT to do | [anti-patterns.md](references/anti-patterns.md) |

---

## Validation Checklist

Before delivering any Dockerfile, verify:

### Security
- [ ] Non-root user configured
- [ ] No hardcoded secrets
- [ ] Base image pinned to specific version
- [ ] Minimal packages installed
- [ ] No unnecessary capabilities

### Optimization
- [ ] Multi-stage build (if level 3+)
- [ ] Dependencies copied before source
- [ ] .dockerignore present
- [ ] No unnecessary files in final image
- [ ] Appropriate base image size

### Best Practices
- [ ] WORKDIR set explicitly
- [ ] Single process per container
- [ ] Health check configured (production)
- [ ] Labels for metadata
- [ ] Clear, documented CMD/ENTRYPOINT

### Testing
- [ ] Image builds successfully
- [ ] Container starts and runs
- [ ] Application accessible on expected port
- [ ] Health check passes (if configured)

---

## Example Outputs by Level

### Level 1: First Dockerfile (Python)

```dockerfile
# Use Python 3.12 slim image (smaller than full image)
FROM python:3.12-slim

# Set working directory inside container
WORKDIR /app

# Copy requirements first (for layer caching)
# This layer is cached if requirements.txt hasn't changed
COPY requirements.txt .

# Install Python dependencies
# --no-cache-dir reduces image size
RUN pip install --no-cache-dir -r requirements.txt

# Copy application code
COPY . .

# Document the port your app uses
EXPOSE 8000

# Command to run the application
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### Level 4: Production-Ready (Python)

```dockerfile
# Build stage
FROM python:3.12-slim AS builder
WORKDIR /app

# Install build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.12-slim
WORKDIR /app

# Create non-root user
RUN useradd --create-home --uid 1000 appuser

# Copy dependencies from builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy application
COPY --chown=appuser:appuser . .

# Configure environment
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

EXPOSE 8000

CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## Scripts

### Dockerfile Analysis
```bash
./scripts/analyze-dockerfile.sh <path-to-dockerfile>
```
Checks for common issues, anti-patterns, and optimization opportunities.

### Security Scan
```bash
./scripts/security-scan.sh <path-to-dockerfile>
```
Performs basic security checks on the Dockerfile.

---

## Related Skills

- **fastapi-builder**: For building FastAPI applications before containerizing
- **pytest**: For setting up tests that run in CI/CD pipelines
