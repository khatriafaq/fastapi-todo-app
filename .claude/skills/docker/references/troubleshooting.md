# Docker Troubleshooting Guide

Solutions for common Docker build errors, runtime issues, and debugging techniques.

---

## Build Errors

### "COPY failed: file not found"

**Symptoms:**
```
COPY failed: file not found in build context or excluded by .dockerignore
```

**Causes & Solutions:**

1. **File not in build context:**
   ```bash
   # Check if file exists
   ls -la <filename>

   # Build from correct directory
   docker build -f path/to/Dockerfile .
   ```

2. **File excluded by .dockerignore:**
   ```bash
   # Check .dockerignore
   cat .dockerignore

   # Remove or comment out the pattern
   ```

3. **Wrong path in COPY:**
   ```dockerfile
   # Wrong - absolute path on host
   COPY /home/user/file.txt /app/

   # Correct - relative to build context
   COPY file.txt /app/
   ```

---

### "pip install" fails

**Symptoms:**
```
ERROR: Could not find a version that satisfies the requirement
ERROR: Failed building wheel for <package>
```

**Solutions:**

1. **Missing build dependencies:**
   ```dockerfile
   # Install build tools first
   RUN apt-get update && apt-get install -y --no-install-recommends \
       build-essential \
       libpq-dev \
       && rm -rf /var/lib/apt/lists/*
   ```

2. **Python version mismatch:**
   ```dockerfile
   # Ensure correct Python version
   FROM python:3.12-slim  # Match project's Python version
   ```

3. **Network issues:**
   ```bash
   # Try with different index
   RUN pip install --index-url https://pypi.org/simple/ -r requirements.txt
   ```

---

### "npm install" fails

**Symptoms:**
```
npm ERR! code ERESOLVE
npm ERR! network timeout
npm ERR! permission denied
```

**Solutions:**

1. **Use npm ci instead of install:**
   ```dockerfile
   # Reproducible, faster
   COPY package*.json ./
   RUN npm ci
   ```

2. **Clear npm cache:**
   ```dockerfile
   RUN npm ci && npm cache clean --force
   ```

3. **Permission issues:**
   ```dockerfile
   # Set npm cache location
   RUN npm config set cache /tmp/.npm
   ```

---

### "go build" fails

**Symptoms:**
```
go: module requires Go 1.22
cannot find package
```

**Solutions:**

1. **Go version mismatch:**
   ```dockerfile
   # Match go.mod version
   FROM golang:1.22  # Check go.mod for version
   ```

2. **Missing go.sum:**
   ```dockerfile
   COPY go.mod go.sum ./
   RUN go mod download
   ```

3. **CGO issues:**
   ```dockerfile
   # Disable CGO for static builds
   RUN CGO_ENABLED=0 go build -o app .
   ```

---

## Runtime Errors

### "exec format error"

**Symptoms:**
```
exec /app/server: exec format error
standard_init_linux.go: exec user process caused: exec format error
```

**Causes & Solutions:**

1. **Architecture mismatch (building on M1 Mac for x86):**
   ```bash
   # Build for specific platform
   docker build --platform linux/amd64 .
   ```

2. **Missing shebang in script:**
   ```bash
   # Add shebang to script
   #!/bin/bash
   ```

3. **Binary built for wrong OS:**
   ```dockerfile
   # Ensure correct GOOS/GOARCH
   RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -o app .
   ```

---

### "permission denied"

**Symptoms:**
```
permission denied
EACCES: permission denied
```

**Solutions:**

1. **File permissions:**
   ```dockerfile
   # Set correct ownership
   COPY --chown=appuser:appuser . /app/

   # Or fix permissions
   RUN chmod +x /app/entrypoint.sh
   ```

2. **Running as non-root but files owned by root:**
   ```dockerfile
   RUN chown -R appuser:appuser /app
   USER appuser
   ```

3. **Volume mount permissions:**
   ```bash
   # Match container user UID
   docker run -u $(id -u):$(id -g) -v ./data:/data myapp
   ```

---

### "address already in use"

**Symptoms:**
```
Error starting userland proxy: listen tcp4 0.0.0.0:8000: bind: address already in use
```

**Solutions:**

1. **Find and kill process:**
   ```bash
   # Find what's using the port
   lsof -i :8000
   # or
   netstat -tulpn | grep 8000

   # Kill the process
   kill -9 <PID>
   ```

2. **Stop existing container:**
   ```bash
   docker ps
   docker stop <container_id>
   ```

3. **Use different port:**
   ```bash
   docker run -p 8001:8000 myapp
   ```

---

### "connection refused"

**Symptoms:**
```
Connection refused
ECONNREFUSED 127.0.0.1:8000
```

**Solutions:**

1. **App not binding to 0.0.0.0:**
   ```python
   # Wrong
   app.run(host='localhost')

   # Correct
   app.run(host='0.0.0.0')
   ```

2. **Container networking issue:**
   ```bash
   # Check container is running
   docker ps

   # Check logs
   docker logs <container_id>

   # Check port mapping
   docker port <container_id>
   ```

3. **Service not ready yet:**
   ```bash
   # Add health check and wait
   docker run -d --health-cmd="curl -f localhost:8000/health" myapp
   ```

---

### Container exits immediately

**Symptoms:**
```
Exited (0) 1 second ago
Exited (1) 1 second ago
```

**Solutions:**

1. **Check logs:**
   ```bash
   docker logs <container_id>
   ```

2. **Command completes and exits:**
   ```dockerfile
   # Wrong - runs and exits
   CMD ["echo", "hello"]

   # Correct - keeps running
   CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0"]
   ```

3. **Application crashes:**
   ```bash
   # Run interactively to debug
   docker run -it myapp /bin/bash
   ```

4. **Process runs in background:**
   ```dockerfile
   # Wrong - backgrounded, container exits
   CMD ["python", "app.py", "&"]

   # Correct - foreground
   CMD ["python", "app.py"]
   ```

---

## Debugging Techniques

### Inspect Running Container

```bash
# Get a shell in running container
docker exec -it <container_id> /bin/bash

# For alpine (no bash)
docker exec -it <container_id> /bin/sh

# Run command without shell
docker exec <container_id> ps aux
```

### Inspect Failed Build

```bash
# Build with progress output
docker build --progress=plain .

# Build and keep intermediate containers
docker build --rm=false .

# Get shell in intermediate layer
docker run -it <intermediate_image_id> /bin/bash
```

### View Logs

```bash
# View all logs
docker logs <container_id>

# Follow logs
docker logs -f <container_id>

# Last 100 lines
docker logs --tail 100 <container_id>

# With timestamps
docker logs -t <container_id>
```

### Network Debugging

```bash
# Inspect container networking
docker inspect <container_id> | jq '.[0].NetworkSettings'

# List networks
docker network ls

# Inspect network
docker network inspect <network_name>

# Test connectivity between containers
docker exec container1 ping container2
```

### Resource Issues

```bash
# Check container resource usage
docker stats <container_id>

# Check disk usage
docker system df

# Clean up
docker system prune -a
```

---

## Common Error Messages Quick Reference

| Error | Likely Cause | Quick Fix |
|-------|--------------|-----------|
| "file not found" | Wrong path or .dockerignore | Check file path and .dockerignore |
| "exec format error" | Architecture mismatch | Build with --platform |
| "permission denied" | File ownership/permissions | Use --chown or fix permissions |
| "address in use" | Port conflict | Stop other container or change port |
| "connection refused" | Binding to localhost | Use 0.0.0.0 |
| "no space left" | Disk full | docker system prune |
| "OOMKilled" | Out of memory | Increase --memory limit |
| "unhealthy" | Health check failing | Check logs, fix health endpoint |

---

## Health Check Debugging

```bash
# Check health status
docker inspect --format='{{json .State.Health}}' <container_id> | jq

# View health check logs
docker inspect --format='{{json .State.Health.Log}}' <container_id> | jq

# Run health check manually
docker exec <container_id> curl -f http://localhost:8000/health
```
