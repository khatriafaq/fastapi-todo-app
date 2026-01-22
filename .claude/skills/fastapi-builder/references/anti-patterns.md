# FastAPI Anti-Patterns

Common mistakes that quietly kill throughput, security, and maintainability.

## 1. Blocking the Event Loop

### ❌ The Problem

```python
import time
import requests  # Sync HTTP library

@app.get("/slow")
async def slow_endpoint():
    time.sleep(5)  # BLOCKS ALL REQUESTS FOR 5 SECONDS
    return {"status": "done"}

@app.get("/external")
async def call_external_api():
    response = requests.get("https://api.example.com/data")  # BLOCKS!
    return response.json()
```

**Impact**: Single slow request freezes entire application. 100% CPU usage, zero throughput.

### ✅ The Fix

```python
import asyncio
import httpx  # Async HTTP library

@app.get("/slow")
async def slow_endpoint():
    await asyncio.sleep(5)  # Other requests can process
    return {"status": "done"}

@app.get("/external")
async def call_external_api():
    async with httpx.AsyncClient() as client:
        response = await client.get("https://api.example.com/data")
        return response.json()

# OR: Run blocking code in threadpool
from fastapi.concurrency import run_in_threadpool

@app.get("/cpu-intensive")
async def cpu_intensive():
    result = await run_in_threadpool(expensive_computation, data)
    return {"result": result}
```

---

## 2. Sync Database with Async App

### ❌ The Problem

```python
# Using sync SQLAlchemy in async routes
from sqlalchemy import create_engine
from sqlalchemy.orm import Session

engine = create_engine("postgresql://user:pass@localhost/db")

@app.get("/users/{user_id}")
async def get_user(user_id: int):
    db = Session(bind=engine)
    user = db.query(User).filter(User.id == user_id).first()  # BLOCKS!
    db.close()
    return user
```

**Impact**: Blocks event loop on every database call. Defeats purpose of async.

### ✅ The Fix

```python
# Use async SQLAlchemy
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker

engine = create_async_engine("postgresql+asyncpg://user:pass@localhost/db")
AsyncSessionLocal = async_sessionmaker(engine, class_=AsyncSession)

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session

@app.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).filter(User.id == user_id))
    return result.scalar_one_or_none()
```

---

## 3. Hardcoded Secrets

### ❌ The Problem

```python
# Secrets in code (committed to git!)
SECRET_KEY = "super-secret-key-12345"
DATABASE_URL = "postgresql://admin:P@ssw0rd@prod.example.com/db"
API_KEY = "sk-1234567890abcdef"

app = FastAPI()
```

**Impact**: Security breach, leaked credentials, unauthorized access.

### ✅ The Fix

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    SECRET_KEY: str
    DATABASE_URL: str
    API_KEY: str

    class Config:
        env_file = ".env"

settings = Settings()

# .env (NEVER commit to git)
SECRET_KEY=randomly-generated-secret-here
DATABASE_URL=postgresql://admin:P@ssw0rd@prod.example.com/db
API_KEY=sk-1234567890abcdef

# .gitignore
.env
*.env
```

---

## 4. Missing Input Validation

### ❌ The Problem

```python
@app.post("/users/")
async def create_user(request: Request):
    data = await request.json()  # No validation!
    email = data["email"]  # Could be missing, could be malicious
    db_user = User(email=email)
    db.add(db_user)
    await db.commit()
    return db_user
```

**Impact**: SQL injection, XSS, type errors, crashes.

### ✅ The Fix

```python
from pydantic import BaseModel, EmailStr, Field, validator

class UserCreate(BaseModel):
    email: EmailStr  # Validates email format
    username: str = Field(..., min_length=3, max_length=50, pattern="^[a-zA-Z0-9_]+$")
    age: int = Field(..., ge=0, le=150)

    @validator('username')
    def username_must_be_alphanumeric(cls, v):
        assert v.isalnum() or '_' in v, 'must be alphanumeric'
        return v

@app.post("/users/")
async def create_user(user: UserCreate, db: AsyncSession = Depends(get_db)):
    # user is validated, guaranteed to have correct types/formats
    db_user = User(email=user.email, username=user.username, age=user.age)
    db.add(db_user)
    await db.commit()
    return db_user
```

---

## 5. Wildcard CORS in Production

### ❌ The Problem

```python
from fastapi.middleware.cors import CORSMiddleware

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # ANY WEBSITE CAN ACCESS YOUR API!
    allow_credentials=True,  # And steal user cookies/tokens
    allow_methods=["*"],
    allow_headers=["*"],
)
```

**Impact**: CSRF attacks, credential theft, data leakage.

### ✅ The Fix

```python
# Development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:3000"],
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
)

# Production
app.add_middleware(
    CORSMiddleware,
    allow_origins=[
        "https://myapp.com",
        "https://www.myapp.com"
    ],  # Explicit whitelist
    allow_credentials=True,
    allow_methods=["GET", "POST", "PUT", "DELETE"],
    allow_headers=["Authorization", "Content-Type"],
    max_age=3600,
)
```

---

## 6. N+1 Query Problem

### ❌ The Problem

```python
@app.get("/users-with-items")
async def get_users_with_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).limit(100))
    users = result.scalars().all()

    for user in users:
        # Separate query for EACH user's items
        items_result = await db.execute(
            select(Item).filter(Item.owner_id == user.id)
        )
        user.items = items_result.scalars().all()

    return users
    # 1 query for users + 100 queries for items = 101 queries!
```

**Impact**: Massive database load, slow responses, poor scalability.

### ✅ The Fix

```python
from sqlalchemy.orm import selectinload

@app.get("/users-with-items")
async def get_users_with_items(db: AsyncSession = Depends(get_db)):
    result = await db.execute(
        select(User)
        .options(selectinload(User.items))  # Eager load in 1-2 queries
        .limit(100)
    )
    users = result.scalars().all()
    return users
    # 1 query for users + 1 query for all items = 2 queries total
```

---

## 7. Error Handling Leaks

### ❌ The Problem

```python
@app.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail=f"User {user_id} not found in database table 'users' at PostgreSQL server prod-db-01.internal:5432")
    return user

# OR: No error handling at all, exposing stack traces
@app.get("/process")
async def process():
    result = buggy_function()  # Crashes with 500 and full stack trace
    return result
```

**Impact**: Leaks internal architecture, database details, stack traces. Security risk.

### ✅ The Fix

```python
import logging

logger = logging.getLogger(__name__)

@app.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    user = await db.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    return user

@app.get("/process")
async def process():
    try:
        result = buggy_function()
        return result
    except Exception as e:
        logger.error(f"Error in /process: {e}", exc_info=True)  # Log internally
        raise HTTPException(status_code=500, detail="Internal server error")

# Global exception handler
@app.exception_handler(Exception)
async def global_exception_handler(request: Request, exc: Exception):
    logger.error(f"Unhandled exception: {exc}", exc_info=True)
    return JSONResponse(
        status_code=500,
        content={"detail": "Internal server error"}
    )
```

---

## 8. No Pagination

### ❌ The Problem

```python
@app.get("/users")
async def get_all_users(db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User))
    return result.scalars().all()
    # Could be 1 million users! OOM crash, slow response
```

**Impact**: Out of memory, slow responses, database overload.

### ✅ The Fix

```python
from fastapi import Query

@app.get("/users")
async def get_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db)
):
    skip = (page - 1) * page_size
    result = await db.execute(
        select(User).offset(skip).limit(page_size)
    )
    users = result.scalars().all()

    total = await db.scalar(select(func.count(User.id)))

    return {
        "users": users,
        "page": page,
        "page_size": page_size,
        "total": total,
        "pages": (total + page_size - 1) // page_size
    }
```

---

## 9. Global Mutable State

### ❌ The Problem

```python
# Global variable shared across requests
user_cache = {}

@app.post("/login")
async def login(email: str, password: str):
    user = authenticate(email, password)
    user_cache[email] = user  # Race condition! Not thread-safe
    return {"token": "..."}

@app.get("/profile")
async def profile(email: str):
    return user_cache.get(email)  # Could return another user's data!
```

**Impact**: Race conditions, data corruption, security vulnerabilities.

### ✅ The Fix

```python
# Use proper state management (Redis, database, or request-scoped state)
from fastapi import Depends
from redis import asyncio as aioredis

async def get_redis():
    redis = await aioredis.from_url("redis://localhost")
    try:
        yield redis
    finally:
        await redis.close()

@app.post("/login")
async def login(
    email: str,
    password: str,
    redis: aioredis.Redis = Depends(get_redis)
):
    user = await authenticate(email, password)
    token = create_token(user)
    await redis.setex(f"session:{token}", 3600, user.id)  # Thread-safe
    return {"token": token}

@app.get("/profile")
async def profile(
    current_user: User = Depends(get_current_user)  # From JWT, not global state
):
    return current_user
```

---

## 10. Missing Database Indexes

### ❌ The Problem

```python
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True)
    email = Column(String)  # No index!
    username = Column(String)  # No index!
    created_at = Column(DateTime)  # No index!

# Query scans entire table (slow!)
@app.get("/users/by-email")
async def get_user_by_email(email: str, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).filter(User.email == email))
    return result.scalar_one_or_none()
```

**Impact**: Slow queries, high database CPU, poor scalability.

### ✅ The Fix

```python
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)  # Index for lookups
    username = Column(String, unique=True, index=True)
    created_at = Column(DateTime, index=True)  # Index for sorting

    # Composite index for combined queries
    __table_args__ = (
        Index('ix_user_email_active', 'email', 'is_active'),
    )
```

---

## 11. Dependency Injection Abuse

### ❌ The Problem

```python
# Creating heavy resources for every request
async def get_ml_model():
    model = load_huge_ml_model()  # Loads 2GB model EVERY REQUEST!
    return model

@app.post("/predict")
async def predict(data: dict, model = Depends(get_ml_model)):
    return model.predict(data)
```

**Impact**: High memory usage, slow startup, resource exhaustion.

### ✅ The Fix

```python
# Load once at startup
ml_model = None

@app.on_event("startup")
async def load_model():
    global ml_model
    ml_model = load_huge_ml_model()  # Load once

@app.post("/predict")
async def predict(data: dict):
    return ml_model.predict(data)

# OR: Use functools.lru_cache for dependencies
from functools import lru_cache

@lru_cache()
def get_settings():
    return Settings()  # Loaded once, cached forever

@app.get("/config")
async def get_config(settings: Settings = Depends(get_settings)):
    return settings
```

---

## 12. Ignoring Response Models

### ❌ The Problem

```python
@app.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    user = await db.get(User, user_id)
    return user  # Returns EVERYTHING including hashed_password, internal fields!
```

**Impact**: Leaks sensitive data, bloated responses, security risk.

### ✅ The Fix

```python
from pydantic import BaseModel

class UserPublic(BaseModel):
    id: int
    email: str
    username: str
    # Explicitly exclude: hashed_password, is_superuser, etc.

    class Config:
        from_attributes = True

@app.get("/users/{user_id}", response_model=UserPublic)
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    user = await db.get(User, user_id)
    return user  # FastAPI filters to only UserPublic fields
```

---

## 13. Sequential External Calls

### ❌ The Problem

```python
import httpx

@app.get("/dashboard")
async def dashboard():
    async with httpx.AsyncClient() as client:
        users = await client.get("https://api.example.com/users")
        items = await client.get("https://api.example.com/items")
        stats = await client.get("https://api.example.com/stats")

    return {
        "users": users.json(),
        "items": items.json(),
        "stats": stats.json()
    }
    # Takes 3 seconds if each call takes 1 second
```

**Impact**: Slow responses, wasted time waiting sequentially.

### ✅ The Fix

```python
import asyncio
import httpx

@app.get("/dashboard")
async def dashboard():
    async with httpx.AsyncClient() as client:
        users_task = client.get("https://api.example.com/users")
        items_task = client.get("https://api.example.com/items")
        stats_task = client.get("https://api.example.com/stats")

        users, items, stats = await asyncio.gather(users_task, items_task, stats_task)

    return {
        "users": users.json(),
        "items": items.json(),
        "stats": stats.json()
    }
    # Takes 1 second (all requests in parallel)
```

---

## 14. Missing Health Checks

### ❌ The Problem

```python
# No health check endpoint
# Load balancers and orchestrators can't verify if app is healthy
```

**Impact**: Traffic routed to unhealthy instances, cascading failures.

### ✅ The Fix

```python
@app.get("/health")
async def health_check():
    return {"status": "ok"}

@app.get("/health/ready")
async def readiness_check(db: AsyncSession = Depends(get_db)):
    try:
        # Check database connection
        await db.execute(text("SELECT 1"))
        return {"status": "ready", "database": "ok"}
    except Exception as e:
        return JSONResponse(
            status_code=503,
            content={"status": "not ready", "database": "error"}
        )
```

---

## 15. Debug Mode in Production

### ❌ The Problem

```python
# Exposes stack traces, internal paths, debug info to users
app = FastAPI(debug=True)
```

**Impact**: Information leakage, security risk, performance overhead.

### ✅ The Fix

```python
from app.core.config import settings

app = FastAPI(
    debug=settings.DEBUG,  # False in production
    docs_url=None if not settings.DEBUG else "/docs",  # Disable docs in prod
    redoc_url=None if not settings.DEBUG else "/redoc",
)
```

---

## Summary: Anti-Pattern Checklist

Before deploying, verify you're NOT doing these:

- [ ] Blocking the event loop with sync I/O
- [ ] Using sync database drivers (psycopg2, pymongo)
- [ ] Hardcoding secrets in code
- [ ] Missing input validation
- [ ] Wildcard CORS (`allow_origins=["*"]`)
- [ ] N+1 query problems
- [ ] Exposing error details to users
- [ ] No pagination on list endpoints
- [ ] Global mutable state
- [ ] Missing database indexes
- [ ] Heavy resources in dependencies
- [ ] Returning full models without response_model
- [ ] Sequential external API calls
- [ ] Missing health check endpoints
- [ ] Debug mode enabled in production

Fix these anti-patterns = 10x throughput, security, and maintainability.
