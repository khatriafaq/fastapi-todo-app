# Dockerfile Patterns by Language

Language-specific Dockerfile patterns with package manager variations and best practices.

---

## Python

### With pip (requirements.txt)

**Development:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

EXPOSE 8000
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

**Production (Multi-stage):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

FROM python:3.12-slim
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . .

ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### With Poetry

**Development:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app

RUN pip install poetry
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi

COPY . .
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

**Production (Multi-stage):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app

RUN pip install poetry
COPY pyproject.toml poetry.lock ./
RUN poetry config virtualenvs.create false \
    && poetry install --no-interaction --no-ansi --only main

FROM python:3.12-slim
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin
COPY --chown=appuser:appuser . .

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser
EXPOSE 8000
CMD ["python", "-m", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

### With uv (Fast Python Package Manager)

**Development:**
```dockerfile
FROM python:3.12-slim
WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

COPY . .
EXPOSE 8000
CMD ["uv", "run", "uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000", "--reload"]
```

**Production (Multi-stage):**
```dockerfile
FROM python:3.12-slim AS builder
WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

COPY pyproject.toml uv.lock ./
RUN uv sync --frozen --no-dev

FROM python:3.12-slim
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser
COPY --from=builder /app/.venv /app/.venv
COPY --chown=appuser:appuser . .

ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

USER appuser
EXPOSE 8000
CMD ["uvicorn", "main:app", "--host", "0.0.0.0", "--port", "8000"]
```

---

## Node.js

### With npm

**Development:**
```dockerfile
FROM node:20-slim
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
EXPOSE 3000
CMD ["npm", "run", "dev"]
```

**Production (Multi-stage):**
```dockerfile
FROM node:20-slim AS builder
WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .
RUN npm run build

FROM node:20-slim
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser

COPY --from=builder /app/package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY --from=builder --chown=appuser:appuser /app/dist ./dist

ENV NODE_ENV=production
USER appuser
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

### With yarn

**Development:**
```dockerfile
FROM node:20-slim
WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .
EXPOSE 3000
CMD ["yarn", "dev"]
```

**Production (Multi-stage):**
```dockerfile
FROM node:20-slim AS builder
WORKDIR /app

COPY package.json yarn.lock ./
RUN yarn install --frozen-lockfile

COPY . .
RUN yarn build

FROM node:20-slim
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser

COPY --from=builder /app/package.json /app/yarn.lock ./
RUN yarn install --frozen-lockfile --production && yarn cache clean

COPY --from=builder --chown=appuser:appuser /app/dist ./dist

ENV NODE_ENV=production
USER appuser
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

### With pnpm

**Development:**
```dockerfile
FROM node:20-slim
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
EXPOSE 3000
CMD ["pnpm", "dev"]
```

**Production (Multi-stage):**
```dockerfile
FROM node:20-slim AS builder
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate

COPY package.json pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile

COPY . .
RUN pnpm build

FROM node:20-slim
WORKDIR /app

RUN corepack enable && corepack prepare pnpm@latest --activate
RUN useradd --create-home --uid 1000 appuser

COPY --from=builder /app/package.json /app/pnpm-lock.yaml ./
RUN pnpm install --frozen-lockfile --prod

COPY --from=builder --chown=appuser:appuser /app/dist ./dist

ENV NODE_ENV=production
USER appuser
EXPOSE 3000
CMD ["node", "dist/index.js"]
```

---

## Go

### Standard (with scratch)

**Production (Minimal):**
```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/server ./cmd/server

FROM scratch
WORKDIR /app

COPY --from=builder /app/server .
COPY --from=builder /etc/ssl/certs/ca-certificates.crt /etc/ssl/certs/

EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

### With Distroless (Recommended for debugging)

```dockerfile
FROM golang:1.22 AS builder
WORKDIR /app

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -ldflags="-w -s" -o /app/server ./cmd/server

FROM gcr.io/distroless/static:nonroot
WORKDIR /app

COPY --from=builder /app/server .

USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

### With Alpine (When shell access needed)

```dockerfile
FROM golang:1.22-alpine AS builder
WORKDIR /app

RUN apk add --no-cache git

COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -ldflags="-w -s" -o /app/server ./cmd/server

FROM alpine:3.19
WORKDIR /app

RUN apk add --no-cache ca-certificates tzdata \
    && adduser -D -u 1000 appuser

COPY --from=builder /app/server .

USER appuser
EXPOSE 8080
ENTRYPOINT ["/app/server"]
```

---

## Rust

**Production:**
```dockerfile
FROM rust:1.75 AS builder
WORKDIR /app

# Cache dependencies
COPY Cargo.toml Cargo.lock ./
RUN mkdir src && echo "fn main() {}" > src/main.rs
RUN cargo build --release
RUN rm -rf src

# Build actual application
COPY . .
RUN touch src/main.rs && cargo build --release

FROM debian:bookworm-slim
WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --create-home --uid 1000 appuser

COPY --from=builder /app/target/release/myapp .

USER appuser
EXPOSE 8080
CMD ["./myapp"]
```

---

## Java (Spring Boot)

**With Maven:**
```dockerfile
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app

COPY pom.xml .
COPY .mvn .mvn
COPY mvnw .
RUN ./mvnw dependency:go-offline

COPY src ./src
RUN ./mvnw package -DskipTests

FROM eclipse-temurin:21-jre
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser
COPY --from=builder /app/target/*.jar app.jar

USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

**With Gradle:**
```dockerfile
FROM eclipse-temurin:21-jdk AS builder
WORKDIR /app

COPY build.gradle.kts settings.gradle.kts ./
COPY gradle ./gradle
COPY gradlew .
RUN ./gradlew dependencies --no-daemon

COPY src ./src
RUN ./gradlew build -x test --no-daemon

FROM eclipse-temurin:21-jre
WORKDIR /app

RUN useradd --create-home --uid 1000 appuser
COPY --from=builder /app/build/libs/*.jar app.jar

USER appuser
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
```

---

## Base Image Quick Reference

| Language | Development | Production | Minimal |
|----------|-------------|------------|---------|
| Python | `python:3.12-slim` | `python:3.12-slim` | `python:3.12-alpine` |
| Node.js | `node:20-slim` | `node:20-slim` | `node:20-alpine` |
| Go | `golang:1.22` | `scratch` or `distroless` | `scratch` |
| Rust | `rust:1.75` | `debian:bookworm-slim` | `scratch` |
| Java | `eclipse-temurin:21-jdk` | `eclipse-temurin:21-jre` | `eclipse-temurin:21-jre-alpine` |
