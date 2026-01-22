# Build stage
FROM python:3.12-slim AS builder
WORKDIR /app

# Install uv
COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

# Copy dependency files
COPY pyproject.toml uv.lock ./

# Install dependencies (excluding dev dependencies)
RUN uv sync --frozen --no-dev

# Runtime stage
FROM python:3.12-slim
WORKDIR /app

# Create non-root user
RUN useradd --create-home --uid 1000 appuser

# Copy virtual environment from builder
COPY --from=builder /app/.venv /app/.venv

# Copy application code
COPY --chown=appuser:appuser app ./app
COPY --chown=appuser:appuser main.py ./

# Set environment variables
ENV PATH="/app/.venv/bin:$PATH" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Switch to non-root user
USER appuser

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/')" || exit 1

# Expose port
EXPOSE 8000

# Labels for Docker Hub
LABEL org.opencontainers.image.title="Todo API" \
      org.opencontainers.image.description="FastAPI Todo application with SQLModel and PostgreSQL" \
      org.opencontainers.image.version="0.1.0" \
      org.opencontainers.image.source="https://github.com/khatriafaq/todo-app"

# Run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
