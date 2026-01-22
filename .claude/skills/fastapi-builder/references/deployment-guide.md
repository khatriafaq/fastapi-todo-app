# FastAPI Deployment Guide

Production deployment guide for FastAPI applications with Docker, ASGI servers, and cloud platforms.

## Deployment Stack

### Recommended Production Stack

```
Internet
    ↓
Reverse Proxy (Nginx/Traefik/Caddy)
    ↓
Load Balancer (if scaled)
    ↓
Process Manager (Gunicorn)
    ↓
ASGI Server (Uvicorn Workers)
    ↓
FastAPI Application
    ↓
Database (PostgreSQL)
```

---

## ASGI Server Configuration

### Uvicorn (Development)

```bash
# Single worker, auto-reload
uvicorn app.main:app --reload --host 0.0.0.0 --port 8000

# Single worker, production
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 1

# Multiple workers (production)
uvicorn app.main:app --host 0.0.0.0 --port 8000 --workers 4
```

### Gunicorn + Uvicorn (Production - Recommended)

```bash
# Install
pip install gunicorn uvicorn[standard]

# Run with Uvicorn workers
gunicorn app.main:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --bind 0.0.0.0:8000 \
  --timeout 30 \
  --graceful-timeout 30 \
  --keep-alive 5 \
  --access-logfile - \
  --error-logfile -
```

**Worker count formula** (async applications):
```
workers = min(2-4 × CPU_cores, 8-12)

# NOT the traditional (2 × CPU_cores) + 1
# That's for sync WSGI apps like Django/Flask
```

### Gunicorn Configuration File

```python
# gunicorn.conf.py
import multiprocessing

# Server Socket
bind = "0.0.0.0:8000"
backlog = 2048

# Worker Processes
workers = multiprocessing.cpu_count() * 2 + 1
worker_class = "uvicorn.workers.UvicornWorker"
worker_connections = 1000
max_requests = 10000
max_requests_jitter = 1000
timeout = 30
graceful_timeout = 30
keepalive = 5

# Logging
accesslog = "-"
errorlog = "-"
loglevel = "info"
access_log_format = '%(h)s %(l)s %(u)s %(t)s "%(r)s" %(s)s %(b)s "%(f)s" "%(a)s" %(D)s'

# Process Naming
proc_name = "fastapi_app"

# Server Mechanics
daemon = False
pidfile = None
user = None
group = None
tmp_upload_dir = None

# SSL (if terminating SSL at Gunicorn)
# keyfile = "/path/to/key.pem"
# certfile = "/path/to/cert.pem"
```

---

## Docker Deployment

### Multi-Stage Dockerfile

```dockerfile
# Build stage
FROM python:3.11-slim as builder

WORKDIR /app

# Install system dependencies
RUN apt-get update && apt-get install -y \
    gcc \
    postgresql-client \
    && rm -rf /var/lib/apt/lists/*

# Install Python dependencies
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Runtime stage
FROM python:3.11-slim

WORKDIR /app

# Install runtime dependencies only
RUN apt-get update && apt-get install -y \
    libpq5 \
    && rm -rf /var/lib/apt/lists/*

# Copy Python dependencies from builder
COPY --from=builder /root/.local /root/.local
ENV PATH=/root/.local/bin:$PATH

# Copy application code
COPY ./app ./app

# Create non-root user
RUN useradd -m -u 1000 appuser && chown -R appuser:appuser /app
USER appuser

# Health check
HEALTH CHECK --interval=30s --timeout=3s --start-period=40s --retries=3 \
    CMD python -c "import requests; requests.get('http://localhost:8000/health', timeout=2)"

# Expose port
EXPOSE 8000

# Run application
CMD ["gunicorn", "app.main:app", \
     "--workers", "4", \
     "--worker-class", "uvicorn.workers.UvicornWorker", \
     "--bind", "0.0.0.0:8000", \
     "--timeout", "30", \
     "--access-logfile", "-", \
     "--error-logfile", "-"]
```

### Docker Compose (Development + Production)

```yaml
version: '3.8'

services:
  # FastAPI Application
  app:
    build:
      context: .
      dockerfile: Dockerfile
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql+asyncpg://postgres:postgres@db:5432/appdb
      - SECRET_KEY=${SECRET_KEY}
      - DEBUG=False
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - ./app:/app/app  # Development only: live code reload
    restart: unless-stopped

  # PostgreSQL Database
  db:
    image: postgres:15-alpine
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
      - POSTGRES_DB=appdb
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped

  # Redis Cache (optional)
  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data
    restart: unless-stopped

  # Nginx Reverse Proxy
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
      - ./ssl:/etc/nginx/ssl:ro  # SSL certificates
    depends_on:
      - app
    restart: unless-stopped

volumes:
  postgres_data:
  redis_data:
```

### Nginx Configuration

```nginx
# nginx.conf
events {
    worker_connections 1024;
}

http {
    upstream fastapi_backend {
        least_conn;
        server app:8000 max_fails=3 fail_timeout=30s;
    }

    # Rate limiting
    limit_req_zone $binary_remote_addr zone=api_limit:10m rate=10r/s;

    server {
        listen 80;
        server_name api.example.com;

        # Redirect HTTP to HTTPS
        return 301 https://$server_name$request_uri;
    }

    server {
        listen 443 ssl http2;
        server_name api.example.com;

        # SSL Configuration
        ssl_certificate /etc/nginx/ssl/cert.pem;
        ssl_certificate_key /etc/nginx/ssl/key.pem;
        ssl_protocols TLSv1.2 TLSv1.3;
        ssl_ciphers HIGH:!aNULL:!MD5;
        ssl_prefer_server_ciphers on;

        # Security Headers
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "DENY" always;
        add_header X-XSS-Protection "1; mode=block" always;

        # Client body size (for file uploads)
        client_max_body_size 10M;

        # Timeouts
        proxy_connect_timeout 60s;
        proxy_send_timeout 60s;
        proxy_read_timeout 60s;

        # Gzip Compression
        gzip on;
        gzip_types text/plain application/json application/javascript text/css;
        gzip_min_length 1000;

        location / {
            # Rate limiting
            limit_req zone=api_limit burst=20 nodelay;

            # Proxy to FastAPI
            proxy_pass http://fastapi_backend;
            proxy_set_header Host $host;
            proxy_set_header X-Real-IP $remote_addr;
            proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
            proxy_set_header X-Forwarded-Proto $scheme;

            # WebSocket support (if needed)
            proxy_http_version 1.1;
            proxy_set_header Upgrade $http_upgrade;
            proxy_set_header Connection "upgrade";
        }

        # Health check endpoint (no rate limit)
        location /health {
            proxy_pass http://fastapi_backend;
            access_log off;
        }

        # Static files (if serving)
        location /static {
            alias /var/www/static;
            expires 30d;
            add_header Cache-Control "public, immutable";
        }
    }
}
```

---

## Environment Configuration

### .env (Development)

```env
# Application
DEBUG=True
SECRET_KEY=dev-secret-key-change-in-production
ENVIRONMENT=development

# Database
DATABASE_URL=postgresql://postgres:postgres@localhost/appdb
ASYNC_DATABASE_URL=postgresql+asyncpg://postgres:postgres@localhost/appdb

# Redis
REDIS_URL=redis://localhost:6379/0

# CORS
CORS_ORIGINS=http://localhost:3000,http://localhost:8080

# Logging
LOG_LEVEL=DEBUG
```

### .env (Production)

```env
# Application
DEBUG=False
SECRET_KEY=randomly-generated-strong-secret-key-here
ENVIRONMENT=production

# Database (use connection pooling service like PgBouncer)
DATABASE_URL=postgresql://user:password@db.example.com/appdb
ASYNC_DATABASE_URL=postgresql+asyncpg://user:password@db.example.com/appdb

# Redis
REDIS_URL=redis://redis.example.com:6379/0

# CORS
CORS_ORIGINS=https://myapp.com,https://www.myapp.com

# Logging
LOG_LEVEL=INFO

# Monitoring
SENTRY_DSN=https://xxx@sentry.io/xxx
```

---

## Cloud Platform Deployment

### AWS ECS (Fargate)

**Task Definition** (JSON):
```json
{
  "family": "fastapi-app",
  "networkMode": "awsvpc",
  "requiresCompatibilities": ["FARGATE"],
  "cpu": "512",
  "memory": "1024",
  "containerDefinitions": [
    {
      "name": "fastapi-app",
      "image": "123456789.dkr.ecr.us-east-1.amazonaws.com/fastapi-app:latest",
      "portMappings": [
        {
          "containerPort": 8000,
          "protocol": "tcp"
        }
      ],
      "environment": [
        {"name": "ENVIRONMENT", "value": "production"}
      ],
      "secrets": [
        {
          "name": "DATABASE_URL",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:db-url"
        },
        {
          "name": "SECRET_KEY",
          "valueFrom": "arn:aws:secretsmanager:region:account:secret:api-secret"
        }
      ],
      "logConfiguration": {
        "logDriver": "awslogs",
        "options": {
          "awslogs-group": "/ecs/fastapi-app",
          "awslogs-region": "us-east-1",
          "awslogs-stream-prefix": "ecs"
        }
      },
      "healthCheck": {
        "command": ["CMD-SHELL", "curl -f http://localhost:8000/health || exit 1"],
        "interval": 30,
        "timeout": 5,
        "retries": 3,
        "startPeriod": 60
      }
    }
  ]
}
```

### Google Cloud Run

```bash
# Build and push image
gcloud builds submit --tag gcr.io/PROJECT_ID/fastapi-app

# Deploy
gcloud run deploy fastapi-app \
  --image gcr.io/PROJECT_ID/fastapi-app \
  --platform managed \
  --region us-central1 \
  --allow-unauthenticated \
  --set-env-vars "ENVIRONMENT=production" \
  --set-secrets "DATABASE_URL=database-url:latest" \
  --set-secrets "SECRET_KEY=api-secret:latest" \
  --cpu 2 \
  --memory 1Gi \
  --min-instances 1 \
  --max-instances 10 \
  --timeout 300 \
  --port 8000
```

### Heroku

```bash
# Create Procfile
echo "web: gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:\$PORT" > Procfile

# Deploy
heroku create my-fastapi-app
heroku addons:create heroku-postgresql:hobby-dev
heroku config:set SECRET_KEY=your-secret-key
git push heroku main
```

### Kubernetes

```yaml
# deployment.yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: fastapi-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: fastapi-app
  template:
    metadata:
      labels:
        app: fastapi-app
    spec:
      containers:
      - name: fastapi-app
        image: your-registry/fastapi-app:latest
        ports:
        - containerPort: 8000
        env:
        - name: ENVIRONMENT
          value: "production"
        envFrom:
        - secretRef:
            name: fastapi-secrets
        resources:
          requests:
            memory: "512Mi"
            cpu: "500m"
          limits:
            memory: "1Gi"
            cpu: "1000m"
        livenessProbe:
          httpGet:
            path: /health
            port: 8000
          initialDelaySeconds: 30
          periodSeconds: 10
        readinessProbe:
          httpGet:
            path: /health/ready
            port: 8000
          initialDelaySeconds: 5
          periodSeconds: 5
---
apiVersion: v1
kind: Service
metadata:
  name: fastapi-service
spec:
  selector:
    app: fastapi-app
  ports:
  - protocol: TCP
    port: 80
    targetPort: 8000
  type: LoadBalancer
---
apiVersion: autoscaling/v2
kind: HorizontalPodAutoscaler
metadata:
  name: fastapi-hpa
spec:
  scaleTargetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: fastapi-app
  minReplicas: 2
  maxReplicas: 10
  metrics:
  - type: Resource
    resource:
      name: cpu
      target:
        type: Utilization
        averageUtilization: 70
```

---

## Database Migrations in Production

### Alembic Migration Strategy

```bash
# Before deploying new code version:

# 1. Create migration
alembic revision --autogenerate -m "Description of changes"

# 2. Review generated migration
# Edit alembic/versions/xxx_description.py if needed

# 3. Test migration on staging
alembic upgrade head

# 4. Include migration in deployment
# Option A: Run migration in CI/CD before deploying app
# Option B: Run migration in init container (Kubernetes)
# Option C: Run migration manually before deployment
```

### Zero-Downtime Migrations

**Strategy**: Backward-compatible changes only

```python
# ✅ SAFE - Add new optional column
def upgrade():
    op.add_column('users', sa.Column('phone', sa.String(), nullable=True))

# ✅ SAFE - Add new table
def upgrade():
    op.create_table('notifications', ...)

# ❌ RISKY - Remove column (old code will break)
def upgrade():
    op.drop_column('users', 'old_field')  # Deploy code first, then migrate!

# ❌ RISKY - Rename column (requires code changes)
def upgrade():
    op.alter_column('users', 'name', new_column_name='full_name')
```

**Multi-step process for breaking changes**:
1. Deploy code that works with both old and new schema
2. Run migration
3. Deploy code that uses only new schema

---

## Monitoring and Logging

### Structured Logging

```python
# app/core/logging.py
import logging
import sys
from pythonjsonlogger import jsonlogger

def setup_logging():
    logger = logging.getLogger()
    logger.setLevel(logging.INFO)

    handler = logging.StreamHandler(sys.stdout)
    formatter = jsonlogger.JsonFormatter(
        '%(asctime)s %(name)s %(levelname)s %(message)s'
    )
    handler.setFormatter(formatter)
    logger.addHandler(handler)

# app/main.py
from app.core.logging import setup_logging

setup_logging()
```

### Prometheus Metrics

```python
from prometheus_client import Counter, Histogram, make_asgi_app
from prometheus_fastapi_instrumentator import Instrumentator

# Initialize metrics
request_count = Counter('http_requests_total', 'Total HTTP requests', ['method', 'endpoint', 'status'])
request_duration = Histogram('http_request_duration_seconds', 'HTTP request duration')

app = FastAPI()

# Auto-instrument
Instrumentator().instrument(app).expose(app, endpoint="/metrics")

# Metrics available at /metrics
```

### Health Checks

```python
@app.get("/health")
async def health():
    return {"status": "ok"}

@app.get("/health/ready")
async def readiness(db: AsyncSession = Depends(get_db)):
    try:
        await db.execute(text("SELECT 1"))
        return {"status": "ready", "database": "ok"}
    except Exception as e:
        logger.error(f"Readiness check failed: {e}")
        return JSONResponse(
            status_code=503,
            content={"status": "not ready", "database": "error"}
        )

@app.get("/health/live")
async def liveness():
    return {"status": "alive"}
```

---

## Security Hardening

### Production Checklist

```python
# app/main.py
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.middleware.trustedhost import TrustedHostMiddleware
from fastapi.middleware.gzip import GZipMiddleware
from app.core.config import settings

app = FastAPI(
    title="My API",
    debug=False,  # CRITICAL: Disable in production
    docs_url=None,  # Disable Swagger UI
    redoc_url=None,  # Disable ReDoc
)

# CORS - Explicit origins only
app.add_middleware(
    CORSMiddleware,
    allow_origins=settings.CORS_ORIGINS.split(","),
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=3600,
)

# Trusted hosts
app.add_middleware(
    TrustedHostMiddleware,
    allowed_hosts=settings.ALLOWED_HOSTS.split(",")
)

# Compression
app.add_middleware(GZipMiddleware, minimum_size=1000)

# Security headers
from starlette.middleware.base import BaseHTTPMiddleware

class SecurityHeadersMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response

app.add_middleware(SecurityHeadersMiddleware)
```

---

## CI/CD Pipeline

### GitHub Actions

```yaml
# .github/workflows/deploy.yml
name: Deploy to Production

on:
  push:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Set up Python
        uses: actions/setup-python@v2
        with:
          python-version: '3.11'
      - name: Install dependencies
        run: |
          pip install -r requirements.txt
          pip install pytest pytest-asyncio
      - name: Run tests
        run: pytest
      - name: Security scan
        run: |
          pip install pip-audit
          pip-audit

  build-and-push:
    needs: test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - name: Build Docker image
        run: docker build -t my-registry/fastapi-app:${{ github.sha }} .
      - name: Push to registry
        run: |
          echo "${{ secrets.REGISTRY_PASSWORD }}" | docker login -u "${{ secrets.REGISTRY_USERNAME }}" --password-stdin
          docker push my-registry/fastapi-app:${{ github.sha }}

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    steps:
      - name: Deploy to production
        run: |
          # Your deployment command (kubectl, aws ecs, etc.)
          kubectl set image deployment/fastapi-app fastapi-app=my-registry/fastapi-app:${{ github.sha }}
```

---

## Production Deployment Checklist

**Application**:
- [ ] `debug=False`
- [ ] `/docs` and `/redoc` disabled (or protected)
- [ ] Secrets from environment variables
- [ ] CORS configured with explicit origins
- [ ] Security headers middleware added
- [ ] Logging configured (structured JSON logs)
- [ ] Health check endpoints implemented

**Server**:
- [ ] Gunicorn + Uvicorn workers
- [ ] Worker count optimized (2-4 per core)
- [ ] Timeouts configured
- [ ] Reverse proxy (Nginx/Traefik)
- [ ] HTTPS/TLS enabled
- [ ] Rate limiting configured

**Database**:
- [ ] Connection pooling configured
- [ ] Migrations tested on staging
- [ ] Backups automated
- [ ] Connection over SSL/TLS

**Monitoring**:
- [ ] Metrics endpoint (/metrics)
- [ ] Structured logging
- [ ] Error tracking (Sentry)
- [ ] Performance monitoring (APM)
- [ ] Alerts configured

**Security**:
- [ ] Dependency vulnerability scanning
- [ ] No hardcoded secrets
- [ ] Input validation on all endpoints
- [ ] Rate limiting on sensitive endpoints
- [ ] Regular security updates

**Infrastructure**:
- [ ] Auto-scaling configured
- [ ] Load balancer health checks
- [ ] CI/CD pipeline
- [ ] Rollback plan
- [ ] Disaster recovery plan

---

## Summary

**Recommended Stack**:
- **Server**: Gunicorn + Uvicorn workers
- **Containerization**: Docker multi-stage builds
- **Orchestration**: Kubernetes or cloud services (ECS, Cloud Run)
- **Reverse Proxy**: Nginx with SSL termination
- **Database**: Managed PostgreSQL with connection pooling
- **Monitoring**: Prometheus + Grafana or cloud-native solutions
- **Logging**: Structured JSON logs to stdout

**Key Principles**:
1. Never expose debug mode or docs in production
2. Use environment-based configuration
3. Implement health checks
4. Monitor everything (metrics, logs, errors)
5. Test deployments on staging first
6. Have a rollback plan
