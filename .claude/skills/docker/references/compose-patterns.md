# Docker Compose Patterns

Common patterns for local development, multi-service applications, and production deployments.

---

## Development Setup

### Basic Development Compose

```yaml
# docker-compose.yml
services:
  app:
    build: .
    ports:
      - "8000:8000"
    volumes:
      - .:/app           # Mount source for hot reload
      - /app/node_modules # Preserve container's node_modules
    environment:
      - DEBUG=true
      - DATABASE_URL=postgres://user:pass@db:5432/myapp
    depends_on:
      - db

  db:
    image: postgres:16
    ports:
      - "5432:5432"
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: pass
      POSTGRES_DB: myapp
    volumes:
      - postgres_data:/var/lib/postgresql/data

volumes:
  postgres_data:
```

### Python Development with Hot Reload

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "8000:8000"
    volumes:
      - .:/app
    environment:
      - PYTHONDONTWRITEBYTECODE=1
      - PYTHONUNBUFFERED=1
    command: uvicorn main:app --host 0.0.0.0 --port 8000 --reload
```

With `Dockerfile.dev`:
```dockerfile
FROM python:3.12-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
# Don't copy source - it will be mounted
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

### Node.js Development

```yaml
services:
  app:
    build:
      context: .
      dockerfile: Dockerfile.dev
    ports:
      - "3000:3000"
    volumes:
      - .:/app
      - /app/node_modules  # Anonymous volume for node_modules
    environment:
      - NODE_ENV=development
    command: npm run dev
```

---

## App + Database Patterns

### FastAPI + PostgreSQL

```yaml
services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:password@db:5432/myapp
    depends_on:
      db:
        condition: service_healthy
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: myapp
    volumes:
      - postgres_data:/var/lib/postgresql/data
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### Node.js + MongoDB

```yaml
services:
  api:
    build: .
    ports:
      - "3000:3000"
    environment:
      - MONGODB_URI=mongodb://mongo:27017/myapp
    depends_on:
      - mongo

  mongo:
    image: mongo:7
    ports:
      - "27017:27017"
    volumes:
      - mongo_data:/data/db

volumes:
  mongo_data:
```

### App + Redis Cache

```yaml
services:
  api:
    build: .
    ports:
      - "8000:8000"
    environment:
      - REDIS_URL=redis://redis:6379
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

volumes:
  redis_data:
```

---

## Full Stack Patterns

### Frontend + Backend + Database

```yaml
services:
  frontend:
    build:
      context: ./frontend
    ports:
      - "3000:3000"
    environment:
      - NEXT_PUBLIC_API_URL=http://localhost:8000
    depends_on:
      - api

  api:
    build:
      context: ./backend
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=postgresql://user:password@db:5432/myapp
      - CORS_ORIGINS=http://localhost:3000
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:16
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: myapp
    volumes:
      - postgres_data:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U user -d myapp"]
      interval: 10s
      timeout: 5s
      retries: 5

volumes:
  postgres_data:
```

### With Nginx Reverse Proxy

```yaml
services:
  nginx:
    image: nginx:alpine
    ports:
      - "80:80"
    volumes:
      - ./nginx.conf:/etc/nginx/nginx.conf:ro
    depends_on:
      - frontend
      - api

  frontend:
    build: ./frontend
    expose:
      - "3000"

  api:
    build: ./backend
    expose:
      - "8000"
    environment:
      - DATABASE_URL=postgresql://user:password@db:5432/myapp
    depends_on:
      - db

  db:
    image: postgres:16
    volumes:
      - postgres_data:/var/lib/postgresql/data
    environment:
      POSTGRES_USER: user
      POSTGRES_PASSWORD: password
      POSTGRES_DB: myapp

volumes:
  postgres_data:
```

---

## Production Patterns

### Production Compose

```yaml
# docker-compose.prod.yml
services:
  app:
    image: ghcr.io/username/myapp:${VERSION:-latest}
    restart: unless-stopped
    ports:
      - "8000:8000"
    environment:
      - DATABASE_URL=${DATABASE_URL}
      - SECRET_KEY=${SECRET_KEY}
    healthcheck:
      test: ["CMD", "curl", "-f", "http://localhost:8000/health"]
      interval: 30s
      timeout: 10s
      retries: 3
      start_period: 40s
    deploy:
      resources:
        limits:
          cpus: '1'
          memory: 512M
        reservations:
          cpus: '0.5'
          memory: 256M
    logging:
      driver: "json-file"
      options:
        max-size: "10m"
        max-file: "3"
```

Run with:
```bash
VERSION=1.0.0 docker compose -f docker-compose.prod.yml up -d
```

### With Environment Files

```yaml
# docker-compose.yml
services:
  app:
    build: .
    env_file:
      - .env
      - .env.local  # Override with local values
```

---

## Override Patterns

### Base + Development Override

```yaml
# docker-compose.yml (base)
services:
  app:
    build: .
    ports:
      - "8000:8000"
```

```yaml
# docker-compose.override.yml (auto-loaded in dev)
services:
  app:
    volumes:
      - .:/app
    environment:
      - DEBUG=true
    command: uvicorn main:app --reload --host 0.0.0.0
```

```yaml
# docker-compose.prod.yml
services:
  app:
    image: myapp:latest
    restart: unless-stopped
    environment:
      - DEBUG=false
```

Usage:
```bash
# Development (uses override automatically)
docker compose up

# Production
docker compose -f docker-compose.yml -f docker-compose.prod.yml up -d
```

---

## Networking

### Internal Services

```yaml
services:
  api:
    build: .
    ports:
      - "8000:8000"  # Exposed externally
    networks:
      - frontend
      - backend

  db:
    image: postgres:16
    # No ports - only accessible internally
    networks:
      - backend

  cache:
    image: redis:7-alpine
    networks:
      - backend

networks:
  frontend:
  backend:
    internal: true  # No external access
```

---

## Useful Commands

```bash
# Start services
docker compose up -d

# View logs
docker compose logs -f

# Stop services
docker compose down

# Stop and remove volumes
docker compose down -v

# Rebuild images
docker compose build --no-cache

# Run one-off command
docker compose run --rm app python manage.py migrate

# Scale services
docker compose up -d --scale worker=3

# View running services
docker compose ps
```

---

## Environment Variable Patterns

### Using .env file
```
# .env
DATABASE_URL=postgresql://user:password@db:5432/myapp
SECRET_KEY=your-secret-key
DEBUG=true
```

### In compose file
```yaml
services:
  app:
    environment:
      # Direct value
      - DEBUG=true
      # From .env or shell
      - DATABASE_URL=${DATABASE_URL}
      # With default
      - LOG_LEVEL=${LOG_LEVEL:-info}
```

### Multiple env files
```yaml
services:
  app:
    env_file:
      - .env           # Base config
      - .env.${ENV}    # Environment-specific (dev, staging, prod)
```
