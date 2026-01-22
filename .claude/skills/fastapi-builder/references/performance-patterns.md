# FastAPI Performance Patterns

This document covers performance optimization techniques for FastAPI applications.

## Performance Principles

1. **Use async correctly**: Don't block the event loop
2. **Minimize I/O**: Cache, batch, parallelize
3. **Optimize queries**: Avoid N+1, use indexes, paginate
4. **Profile first**: Measure before optimizing

---

## Async vs Sync Routes

### Understanding the Event Loop

FastAPI runs on an async event loop. Understanding when to use `async def` vs `def` is critical:

| Route Type | When to Use | How FastAPI Handles It |
|------------|-------------|------------------------|
| `async def` | Async I/O operations (DB, HTTP, file I/O) | Runs directly on event loop |
| `def` (sync) | CPU-bound work, blocking I/O | Runs in threadpool (offloaded) |

### Rule of Thumb

```python
# ✅ Use async def when:
# - Using async libraries (asyncpg, httpx, aiofiles)
# - Awaiting async operations
# - No blocking I/O

@app.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).filter(User.id == user_id))
    return result.scalar_one_or_none()

# ✅ Use def (sync) when:
# - Using sync libraries (requests, psycopg2)
# - CPU-intensive operations
# - No async operations

@app.post("/process")
def process_data(data: ProcessRequest):
    # CPU-intensive work like ML inference
    result = heavy_computation(data)
    return {"result": result}
```

### Common Mistake: Blocking Async Routes

```python
# ❌ BAD - Blocks event loop
import time

@app.get("/slow")
async def slow_endpoint():
    time.sleep(10)  # BLOCKS ALL REQUESTS!
    return {"status": "done"}

# ✅ GOOD - Non-blocking
import asyncio

@app.get("/slow")
async def slow_endpoint():
    await asyncio.sleep(10)  # Other requests can process
    return {"status": "done"}

# ✅ ALSO GOOD - Run blocking code in threadpool
import time
from fastapi.concurrency import run_in_threadpool

@app.get("/slow")
async def slow_endpoint():
    await run_in_threadpool(time.sleep, 10)
    return {"status": "done"}
```

---

## Database Performance

### 1. Use Async Database Drivers

```python
# ✅ GOOD - Async drivers
# PostgreSQL: asyncpg
# MySQL: aiomysql
# SQLite: aiosqlite
# MongoDB: motor

from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine("postgresql+asyncpg://user:pass@localhost/db")
```

### 2. Avoid N+1 Queries

```python
# ❌ BAD - N+1 queries
users = await db.execute(select(User).limit(100))
for user in users.scalars():
    items = await db.execute(select(Item).filter(Item.owner_id == user.id))
    # 1 query for users + 100 queries for items = 101 queries!

# ✅ GOOD - Single query with eager loading
from sqlalchemy.orm import selectinload

users = await db.execute(
    select(User).options(selectinload(User.items)).limit(100)
)
# 1-2 queries total (1 for users, 1 for all items)
```

### 3. Use Connection Pooling

```python
# app/core/database.py
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine(
    settings.ASYNC_DATABASE_URL,
    pool_size=20,           # Connections to keep open
    max_overflow=10,        # Extra connections for spikes
    pool_pre_ping=True,     # Verify connections before use
    pool_recycle=3600,      # Recycle connections hourly
)
```

### 4. Add Database Indexes

```python
# Add indexes to frequently queried columns
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)  # Index for WHERE email =
    created_at = Column(DateTime, index=True)  # Index for ORDER BY created_at

    # Composite index for combined queries
    __table_args__ = (
        Index('ix_user_email_active', 'email', 'is_active'),
    )
```

### 5. Paginate Large Results

```python
# ❌ BAD - Load all records
@app.get("/users")
async def get_users(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User))  # Could be millions!
    return result.scalars().all()

# ✅ GOOD - Paginate
@app.get("/users")
async def get_users(
    page: int = 1,
    page_size: int = 20,
    db: AsyncSession = Depends(get_db)
):
    skip = (page - 1) * page_size
    result = await db.execute(
        select(User).offset(skip).limit(page_size)
    )
    return result.scalars().all()
```

### 6. Select Only Needed Columns

```python
# ❌ BAD - Select all columns
result = await db.execute(select(User))

# ✅ GOOD - Select specific columns
from sqlalchemy import select

result = await db.execute(
    select(User.id, User.email, User.username)
)
```

---

## Caching

### 1. Response Caching

```python
from fastapi_cache import FastAPICache
from fastapi_cache.backends.redis import RedisBackend
from fastapi_cache.decorator import cache
from redis import asyncio as aioredis

# Initialize cache
@app.on_event("startup")
async def startup():
    redis = aioredis.from_url("redis://localhost")
    FastAPICache.init(RedisBackend(redis), prefix="fastapi-cache")

# Cache endpoint responses
@app.get("/users/{user_id}")
@cache(expire=60)  # Cache for 60 seconds
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).filter(User.id == user_id))
    return result.scalar_one_or_none()
```

### 2. In-Memory Caching

```python
from functools import lru_cache

# Cache configuration (reloaded only once)
@lru_cache()
def get_settings():
    return Settings()

# Cache expensive computations
from cachetools import TTLCache
import time

cache = TTLCache(maxsize=100, ttl=300)  # 100 items, 5 min TTL

def expensive_operation(key: str):
    if key in cache:
        return cache[key]

    # Expensive computation
    result = time.sleep(2)  # Simulate
    cache[key] = result
    return result
```

### 3. HTTP Caching Headers

```python
from fastapi import Response
from datetime import datetime, timedelta

@app.get("/public-data")
async def get_public_data(response: Response):
    response.headers["Cache-Control"] = "public, max-age=3600"  # 1 hour
    response.headers["ETag"] = "unique-version-id"
    return {"data": "public information"}

@app.get("/private-data")
async def get_private_data(response: Response):
    response.headers["Cache-Control"] = "private, max-age=300"  # 5 min
    return {"data": "user-specific information"}
```

---

## Parallel Requests

### 1. Concurrent Database Queries

```python
import asyncio

# ❌ BAD - Sequential queries (slow)
@app.get("/dashboard")
async def dashboard(db: AsyncSession = Depends(get_db)):
    users = await get_users(db)
    items = await get_items(db)
    stats = await get_stats(db)
    return {"users": users, "items": items, "stats": stats}

# ✅ GOOD - Parallel queries (fast)
@app.get("/dashboard")
async def dashboard(db: AsyncSession = Depends(get_db)):
    users_task = get_users(db)
    items_task = get_items(db)
    stats_task = get_stats(db)

    users, items, stats = await asyncio.gather(users_task, items_task, stats_task)
    return {"users": users, "items": items, "stats": stats}
```

### 2. External API Calls

```python
import httpx

# ❌ BAD - Sequential external calls
@app.get("/aggregated")
async def get_aggregated():
    async with httpx.AsyncClient() as client:
        response1 = await client.get("https://api1.example.com/data")
        response2 = await client.get("https://api2.example.com/data")
        response3 = await client.get("https://api3.example.com/data")
    return [response1.json(), response2.json(), response3.json()]

# ✅ GOOD - Parallel external calls
@app.get("/aggregated")
async def get_aggregated():
    async with httpx.AsyncClient() as client:
        responses = await asyncio.gather(
            client.get("https://api1.example.com/data"),
            client.get("https://api2.example.com/data"),
            client.get("https://api3.example.com/data"),
        )
    return [r.json() for r in responses]
```

---

## Background Tasks

### 1. FastAPI BackgroundTasks

For simple, quick tasks:

```python
from fastapi import BackgroundTasks

def send_email(email: str, message: str):
    # Send email (takes 2-3 seconds)
    time.sleep(2)
    print(f"Email sent to {email}")

@app.post("/users/")
async def create_user(
    user: UserCreate,
    background_tasks: BackgroundTasks,
    db: AsyncSession = Depends(get_db)
):
    # Create user immediately
    db_user = await create_user_in_db(db, user)

    # Send welcome email in background (non-blocking)
    background_tasks.add_task(send_email, user.email, "Welcome!")

    return db_user  # Return immediately without waiting for email
```

### 2. Celery for Heavy Tasks

For long-running, distributed tasks:

```python
# celery_app.py
from celery import Celery

celery_app = Celery(
    "tasks",
    broker="redis://localhost:6379/0",
    backend="redis://localhost:6379/0"
)

@celery_app.task
def process_video(video_id: int):
    # Long-running task (minutes/hours)
    # Process video, generate thumbnails, etc.
    pass

# router.py
from .celery_app import process_video

@app.post("/videos/")
async def upload_video(video: UploadFile, db: AsyncSession = Depends(get_db)):
    # Save video metadata
    db_video = Video(filename=video.filename, status="processing")
    db.add(db_video)
    await db.commit()

    # Queue processing task
    process_video.delay(db_video.id)

    return {"id": db_video.id, "status": "processing"}
```

---

## Response Optimization

### 1. Response Models

```python
# ✅ Only return needed fields
class UserPublic(BaseModel):
    id: int
    username: str
    email: str
    # Exclude: hashed_password, internal_notes, etc.

@app.get("/users/{user_id}", response_model=UserPublic)
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    # Even if we fetch full User object, only UserPublic fields returned
    result = await db.execute(select(User).filter(User.id == user_id))
    return result.scalar_one_or_none()
```

### 2. Compression

```python
from fastapi.middleware.gzip import GZipMiddleware

app.add_middleware(GZipMiddleware, minimum_size=1000)  # Compress responses >1KB
```

### 3. Streaming Large Responses

```python
from fastapi.responses import StreamingResponse
import asyncio

async def generate_large_data():
    for i in range(10000):
        yield f"data: {i}\n"
        await asyncio.sleep(0.01)  # Simulate processing

@app.get("/stream")
async def stream_data():
    return StreamingResponse(generate_large_data(), media_type="text/plain")
```

---

## Dependency Injection Optimization

### 1. Cache Expensive Dependencies

```python
from functools import lru_cache

# ✅ Cached - computed once
@lru_cache()
def get_settings():
    return Settings()

# Use in dependencies
def get_db_url(settings: Settings = Depends(get_settings)):
    return settings.DATABASE_URL
```

### 2. Dependency Scope

```python
# ❌ BAD - Creates new service instance for every request
async def get_user_service(db: AsyncSession = Depends(get_db)):
    return UserService(db)

# ✅ GOOD - Reuses service instance within request
from contextlib import asynccontextmanager

@asynccontextmanager
async def get_user_service(db: AsyncSession = Depends(get_db)):
    service = UserService(db)
    try:
        yield service
    finally:
        await service.cleanup()
```

---

## Server Configuration

### 1. Uvicorn Workers

```bash
# Single worker (development)
uvicorn app.main:app --reload

# Multiple workers (production)
# Use 2-4 workers per core (async doesn't need many)
uvicorn app.main:app --workers 4 --host 0.0.0.0 --port 8000

# Gunicorn with Uvicorn workers (recommended for production)
gunicorn app.main:app --workers 4 --worker-class uvicorn.workers.UvicornWorker --bind 0.0.0.0:8000
```

### 2. Worker Count Formula

```python
# For async applications (FastAPI)
workers = (2 x num_cores) to (4 x num_cores)

# NOT the traditional: workers = (2 x num_cores) + 1
# That formula is for sync WSGI apps
```

### 3. Timeouts

```bash
# Gunicorn timeouts
gunicorn app.main:app \
  --workers 4 \
  --worker-class uvicorn.workers.UvicornWorker \
  --timeout 30 \          # Worker timeout (seconds)
  --graceful-timeout 30 \ # Graceful shutdown time
  --keep-alive 5          # Keep-alive connections
```

---

## Profiling and Monitoring

### 1. Time Endpoints

```python
import time
from fastapi import Request

@app.middleware("http")
async def add_process_time_header(request: Request, call_next):
    start_time = time.time()
    response = await call_next(request)
    process_time = time.time() - start_time
    response.headers["X-Process-Time"] = str(process_time)
    return response
```

### 2. Prometheus Metrics

```python
from prometheus_fastapi_instrumentator import Instrumentator

# Add metrics endpoint
Instrumentator().instrument(app).expose(app)

# Now available at /metrics
# Includes: request duration, request count, response size, etc.
```

### 3. Logging Slow Queries

```python
import logging
from sqlalchemy import event
from sqlalchemy.engine import Engine

logger = logging.getLogger(__name__)

@event.listens_for(Engine, "before_cursor_execute")
def before_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    conn.info.setdefault('query_start_time', []).append(time.time())

@event.listens_for(Engine, "after_cursor_execute")
def after_cursor_execute(conn, cursor, statement, parameters, context, executemany):
    total = time.time() - conn.info['query_start_time'].pop(-1)
    if total > 1.0:  # Log queries taking >1 second
        logger.warning(f"Slow query ({total:.2f}s): {statement}")
```

---

## Load Testing

### Using Locust

```python
# locustfile.py
from locust import HttpUser, task, between

class FastAPIUser(HttpUser):
    wait_time = between(1, 3)  # Wait 1-3 seconds between requests

    @task(3)  # 3x more frequent than other tasks
    def get_users(self):
        self.client.get("/users")

    @task(1)
    def create_user(self):
        self.client.post("/users", json={
            "email": "test@example.com",
            "username": "testuser",
            "password": "testpass123"
        })

    @task(2)
    def get_user(self):
        self.client.get("/users/1")
```

```bash
# Run load test
locust -f locustfile.py --host http://localhost:8000
# Open http://localhost:8089 to configure and start test
```

---

## Performance Checklist

**Application**:
- [ ] Use `async def` for I/O operations
- [ ] Use `def` for CPU-bound operations
- [ ] No blocking calls in async routes
- [ ] Dependency injection optimized

**Database**:
- [ ] Async database driver (asyncpg, motor)
- [ ] Connection pooling configured
- [ ] Indexes on queried columns
- [ ] No N+1 queries (use eager loading)
- [ ] Pagination for large result sets

**Caching**:
- [ ] Redis/in-memory cache for expensive operations
- [ ] HTTP cache headers for static content
- [ ] Response models to limit data sent

**Concurrency**:
- [ ] Parallel queries with `asyncio.gather()`
- [ ] Background tasks for non-critical work
- [ ] Celery for long-running tasks

**Server**:
- [ ] Multiple Uvicorn workers (2-4 per core)
- [ ] Gunicorn + Uvicorn for production
- [ ] GZip compression enabled
- [ ] Proper timeouts configured

**Monitoring**:
- [ ] Request timing middleware
- [ ] Prometheus metrics
- [ ] Slow query logging
- [ ] Load testing performed

---

## Common Performance Pitfalls

1. **Blocking the event loop** - Using `time.sleep()` or sync I/O in async routes
2. **Too many workers** - Async doesn't need (2 x cores) + 1 formula
3. **Missing indexes** - Slow queries on unindexed columns
4. **N+1 queries** - Loading relationships in loops
5. **No pagination** - Loading thousands of records at once
6. **Sync database** - Using psycopg2 instead of asyncpg
7. **No caching** - Recomputing expensive operations every request
8. **Sequential external calls** - Not using `asyncio.gather()`

---

## Summary

**Golden Rules**:
1. Use async correctly (don't block the event loop)
2. Optimize database queries (indexes, eager loading, pagination)
3. Cache expensive operations
4. Run independent operations in parallel
5. Use background tasks for non-critical work
6. Profile before optimizing
7. Load test before production

Performance is about doing less work, not doing work faster.
