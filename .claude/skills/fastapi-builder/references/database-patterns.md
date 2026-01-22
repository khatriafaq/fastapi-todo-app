# FastAPI Database Patterns

This document covers database integration patterns for FastAPI, focusing on PostgreSQL with async support.

## Database Selection Guide

| Database | Use Case | Async Driver |
|----------|----------|--------------|
| **SQLite** | Development, prototypes, small apps | aiosqlite |
| **PostgreSQL** | Production, complex queries, ACID | asyncpg |
| **MongoDB** | Document storage, flexible schema | motor |
| **MySQL** | Legacy systems, simple relational | aiomysql |

---

## PostgreSQL Setup

### 1. Dependencies

```txt
# requirements.txt
fastapi
uvicorn[standard]
sqlalchemy[asyncio]>=2.0
asyncpg
alembic
psycopg2-binary  # For Alembic migrations
```

### 2. Database Configuration

```python
# app/core/config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    # Sync URL for Alembic migrations
    DATABASE_URL: str = "postgresql://user:password@localhost/dbname"

    # Async URL for application
    ASYNC_DATABASE_URL: str = "postgresql+asyncpg://user:password@localhost/dbname"

    # Connection pool settings
    DB_POOL_SIZE: int = 5
    DB_MAX_OVERFLOW: int = 10

    class Config:
        env_file = ".env"

settings = Settings()
```

### 3. Async Database Engine

```python
# app/core/database.py
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine, async_sessionmaker
from sqlalchemy.orm import declarative_base
from .config import settings

# Create async engine
engine = create_async_engine(
    settings.ASYNC_DATABASE_URL,
    echo=False,  # Set True for SQL logging in development
    pool_size=settings.DB_POOL_SIZE,
    max_overflow=settings.DB_MAX_OVERFLOW,
    pool_pre_ping=True,  # Verify connections before using
)

# Session factory
AsyncSessionLocal = async_sessionmaker(
    engine,
    class_=AsyncSession,
    expire_on_commit=False,
    autocommit=False,
    autoflush=False,
)

Base = declarative_base()

# Dependency for routes
async def get_db() -> AsyncSession:
    async with AsyncSessionLocal() as session:
        try:
            yield session
        finally:
            await session.close()
```

### 4. Database Models

```python
# app/models/user.py
from sqlalchemy import Column, Integer, String, Boolean, DateTime, ForeignKey
from sqlalchemy.orm import relationship
from sqlalchemy.sql import func
from app.core.database import Base

class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True, nullable=False)
    username = Column(String, unique=True, index=True)
    hashed_password = Column(String, nullable=False)
    is_active = Column(Boolean, default=True)
    is_superuser = Column(Boolean, default=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # Relationships
    items = relationship("Item", back_populates="owner")

class Item(Base):
    __tablename__ = "items"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    description = Column(String)
    owner_id = Column(Integer, ForeignKey("users.id"))

    # Relationships
    owner = relationship("User", back_populates="items")
```

---

## CRUD Operations

### Repository Pattern

```python
# app/repositories/user_repository.py
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession
from app.models.user import User
from app.schemas.user import UserCreate
from app.core.security import get_password_hash

class UserRepository:
    def __init__(self, db: AsyncSession):
        self.db = db

    async def get_by_id(self, user_id: int) -> User | None:
        result = await self.db.execute(
            select(User).filter(User.id == user_id)
        )
        return result.scalar_one_or_none()

    async def get_by_email(self, email: str) -> User | None:
        result = await self.db.execute(
            select(User).filter(User.email == email)
        )
        return result.scalar_one_or_none()

    async def get_multi(self, skip: int = 0, limit: int = 100) -> list[User]:
        result = await self.db.execute(
            select(User).offset(skip).limit(limit)
        )
        return result.scalars().all()

    async def create(self, user_in: UserCreate) -> User:
        db_user = User(
            email=user_in.email,
            username=user_in.username,
            hashed_password=get_password_hash(user_in.password),
        )
        self.db.add(db_user)
        await self.db.commit()
        await self.db.refresh(db_user)
        return db_user

    async def update(self, user: User, **kwargs) -> User:
        for key, value in kwargs.items():
            setattr(user, key, value)
        await self.db.commit()
        await self.db.refresh(user)
        return user

    async def delete(self, user: User) -> None:
        await self.db.delete(user)
        await self.db.commit()
```

### Using Repository in Routes

```python
# app/routers/users.py
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.ext.asyncio import AsyncSession
from app.core.database import get_db
from app.repositories.user_repository import UserRepository
from app.schemas.user import User as UserSchema, UserCreate

router = APIRouter(prefix="/users", tags=["users"])

@router.post("/", response_model=UserSchema, status_code=status.HTTP_201_CREATED)
async def create_user(
    user_in: UserCreate,
    db: AsyncSession = Depends(get_db)
):
    repo = UserRepository(db)

    # Check if user exists
    existing_user = await repo.get_by_email(user_in.email)
    if existing_user:
        raise HTTPException(
            status_code=400,
            detail="Email already registered"
        )

    user = await repo.create(user_in)
    return user

@router.get("/{user_id}", response_model=UserSchema)
async def get_user(
    user_id: int,
    db: AsyncSession = Depends(get_db)
):
    repo = UserRepository(db)
    user = await repo.get_by_id(user_id)

    if not user:
        raise HTTPException(status_code=404, detail="User not found")

    return user

@router.get("/", response_model=list[UserSchema])
async def list_users(
    skip: int = 0,
    limit: int = 100,
    db: AsyncSession = Depends(get_db)
):
    repo = UserRepository(db)
    users = await repo.get_multi(skip=skip, limit=limit)
    return users
```

---

## Advanced Queries

### Filtering and Sorting

```python
from sqlalchemy import select, and_, or_

async def search_users(
    db: AsyncSession,
    search: str = None,
    is_active: bool = None,
    sort_by: str = "created_at",
    order: str = "desc"
) -> list[User]:
    query = select(User)

    # Filters
    if search:
        query = query.filter(
            or_(
                User.email.ilike(f"%{search}%"),
                User.username.ilike(f"%{search}%")
            )
        )

    if is_active is not None:
        query = query.filter(User.is_active == is_active)

    # Sorting
    sort_column = getattr(User, sort_by, User.created_at)
    if order == "desc":
        query = query.order_by(sort_column.desc())
    else:
        query = query.order_by(sort_column.asc())

    result = await db.execute(query)
    return result.scalars().all()
```

### Relationships and Joins

```python
from sqlalchemy.orm import selectinload

# Eager loading (avoids N+1 queries)
async def get_user_with_items(db: AsyncSession, user_id: int) -> User | None:
    result = await db.execute(
        select(User)
        .options(selectinload(User.items))  # Load items in same query
        .filter(User.id == user_id)
    )
    return result.scalar_one_or_none()

# Join queries
async def get_items_with_owners(db: AsyncSession) -> list[Item]:
    result = await db.execute(
        select(Item)
        .join(User)
        .options(selectinload(Item.owner))
        .filter(User.is_active == True)
    )
    return result.scalars().all()
```

### Aggregations

```python
from sqlalchemy import func, select

async def get_user_stats(db: AsyncSession) -> dict:
    # Count total users
    total_users = await db.scalar(select(func.count(User.id)))

    # Count active users
    active_users = await db.scalar(
        select(func.count(User.id)).filter(User.is_active == True)
    )

    # Items per user
    items_per_user = await db.execute(
        select(User.username, func.count(Item.id).label('item_count'))
        .join(Item, User.id == Item.owner_id)
        .group_by(User.username)
        .order_by(func.count(Item.id).desc())
    )

    return {
        "total_users": total_users,
        "active_users": active_users,
        "top_users": [
            {"username": row.username, "item_count": row.item_count}
            for row in items_per_user
        ]
    }
```

---

## Database Migrations with Alembic

### Setup Alembic

```bash
# Initialize Alembic
alembic init alembic

# This creates:
# alembic/
#   env.py
#   script.py.mako
#   versions/
# alembic.ini
```

### Configure Alembic

```python
# alembic/env.py
from logging.config import fileConfig
from sqlalchemy import engine_from_config, pool
from alembic import context
from app.core.config import settings
from app.core.database import Base

# Import all models so Alembic can detect them
from app.models.user import User
from app.models.item import Item

config = context.config

# Override sqlalchemy.url from settings
config.set_main_option("sqlalchemy.url", settings.DATABASE_URL)

fileConfig(config.config_file_name)
target_metadata = Base.metadata

def run_migrations_online():
    connectable = engine_from_config(
        config.get_section(config.config_ini_section),
        prefix="sqlalchemy.",
        poolclass=pool.NullPool,
    )

    with connectable.connect() as connection:
        context.configure(
            connection=connection,
            target_metadata=target_metadata,
            compare_type=True,  # Detect column type changes
        )

        with context.begin_transaction():
            context.run_migrations()

run_migrations_online()
```

### Create and Run Migrations

```bash
# Generate migration
alembic revision --autogenerate -m "Add users and items tables"

# Review the generated migration in alembic/versions/

# Run migration
alembic upgrade head

# Rollback
alembic downgrade -1

# Check current version
alembic current
```

### Manual Migration Example

```python
# alembic/versions/xxx_add_user_role.py
from alembic import op
import sqlalchemy as sa

def upgrade():
    op.add_column('users', sa.Column('role', sa.String(), nullable=True))
    op.create_index('ix_users_role', 'users', ['role'])

def downgrade():
    op.drop_index('ix_users_role', 'users')
    op.drop_column('users', 'role')
```

---

## Connection Pooling

### Configuration

```python
# app/core/database.py
from sqlalchemy.ext.asyncio import create_async_engine

engine = create_async_engine(
    settings.ASYNC_DATABASE_URL,

    # Pool settings
    pool_size=5,              # Number of connections to keep open
    max_overflow=10,          # Max connections beyond pool_size
    pool_timeout=30,          # Timeout waiting for connection (seconds)
    pool_recycle=3600,        # Recycle connections after 1 hour
    pool_pre_ping=True,       # Test connection before using

    # Performance
    echo=False,               # Set True to log all SQL
    echo_pool=False,          # Set True to log pool events

    # Future compatibility
    future=True,
)
```

### Best Practices

- **pool_size**: Start with 5, increase if you see "QueuePool limit exceeded"
- **max_overflow**: 2x pool_size for bursts
- **pool_pre_ping**: Always True in production (handles stale connections)
- **pool_recycle**: Set below database's connection timeout

---

## Transactions

### Automatic Transactions

```python
# Each request gets a session, auto-commits on success, rolls back on error
async def create_user_with_profile(db: AsyncSession, user_data, profile_data):
    user = User(**user_data)
    db.add(user)
    await db.flush()  # Get user.id without committing

    profile = Profile(user_id=user.id, **profile_data)
    db.add(profile)

    await db.commit()  # Commits both user and profile
    return user
```

### Manual Transaction Control

```python
from sqlalchemy.exc import SQLAlchemyError

async def transfer_item(db: AsyncSession, item_id: int, from_user_id: int, to_user_id: int):
    try:
        # Start transaction
        item = await db.get(Item, item_id)
        if item.owner_id != from_user_id:
            raise ValueError("Not the owner")

        item.owner_id = to_user_id
        await db.commit()

    except SQLAlchemyError as e:
        await db.rollback()
        raise HTTPException(status_code=500, detail="Transfer failed")
```

---

## Performance Optimization

### 1. Avoid N+1 Queries

```python
# ❌ BAD - N+1 queries (1 for users, N for each user's items)
users = await db.execute(select(User))
for user in users.scalars():
    items = await db.execute(select(Item).filter(Item.owner_id == user.id))
    user.items = items.scalars().all()

# ✅ GOOD - Single query with join
users = await db.execute(
    select(User).options(selectinload(User.items))
)
```

### 2. Indexing

```python
# Add indexes to frequently queried columns
class User(Base):
    __tablename__ = "users"

    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)  # Index for lookups
    username = Column(String, unique=True, index=True)
    created_at = Column(DateTime, index=True)  # Index for sorting

    __table_args__ = (
        Index('ix_users_email_active', 'email', 'is_active'),  # Composite index
    )
```

### 3. Pagination

```python
from fastapi import Query

@router.get("/users")
async def list_users(
    page: int = Query(1, ge=1),
    page_size: int = Query(20, ge=1, le=100),
    db: AsyncSession = Depends(get_db)
):
    skip = (page - 1) * page_size
    limit = page_size

    total = await db.scalar(select(func.count(User.id)))
    users = await db.execute(
        select(User).offset(skip).limit(limit)
    )

    return {
        "total": total,
        "page": page,
        "page_size": page_size,
        "users": users.scalars().all()
    }
```

### 4. Bulk Operations

```python
# Bulk insert
async def create_users_bulk(db: AsyncSession, users_data: list[dict]):
    users = [User(**data) for data in users_data]
    db.add_all(users)
    await db.commit()

# Bulk update
from sqlalchemy import update

async def activate_users(db: AsyncSession, user_ids: list[int]):
    await db.execute(
        update(User)
        .where(User.id.in_(user_ids))
        .values(is_active=True)
    )
    await db.commit()
```

---

## Testing with Database

### In-Memory SQLite for Tests

```python
# tests/conftest.py
import pytest
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession, async_sessionmaker
from app.core.database import Base, get_db
from app.main import app

TEST_DATABASE_URL = "sqlite+aiosqlite:///:memory:"

@pytest.fixture
async def test_db():
    engine = create_async_engine(TEST_DATABASE_URL, echo=False)

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)

    TestSessionLocal = async_sessionmaker(
        engine, class_=AsyncSession, expire_on_commit=False
    )

    async with TestSessionLocal() as session:
        yield session

    async with engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

@pytest.fixture
def override_get_db(test_db):
    async def _get_test_db():
        yield test_db

    app.dependency_overrides[get_db] = _get_test_db
    yield
    app.dependency_overrides.clear()
```

### Test Example

```python
# tests/test_users.py
import pytest
from httpx import AsyncClient
from app.main import app

@pytest.mark.asyncio
async def test_create_user(override_get_db):
    async with AsyncClient(app=app, base_url="http://test") as client:
        response = await client.post("/users/", json={
            "email": "test@example.com",
            "username": "testuser",
            "password": "testpass123"
        })
        assert response.status_code == 201
        assert response.json()["email"] == "test@example.com"
```

---

## Common Pitfalls

### 1. Mixing Sync and Async

```python
# ❌ BAD - Blocking call in async function
async def get_user(db: AsyncSession, user_id: int):
    user = db.query(User).filter(User.id == user_id).first()  # BLOCKS!
    return user

# ✅ GOOD - Async query
async def get_user(db: AsyncSession, user_id: int):
    result = await db.execute(select(User).filter(User.id == user_id))
    return result.scalar_one_or_none()
```

### 2. Session Leaks

```python
# ❌ BAD - Session not closed
async def get_user(user_id: int):
    session = AsyncSessionLocal()
    user = await session.get(User, user_id)
    return user  # Session never closed!

# ✅ GOOD - Context manager
async def get_user(user_id: int):
    async with AsyncSessionLocal() as session:
        user = await session.get(User, user_id)
        return user  # Session auto-closed
```

### 3. Lazy Loading in Async

```python
# ❌ BAD - Lazy loading doesn't work with async
user = await db.get(User, user_id)
items = user.items  # Error! Session may be closed or async context lost

# ✅ GOOD - Eager loading
result = await db.execute(
    select(User).options(selectinload(User.items)).filter(User.id == user_id)
)
user = result.scalar_one_or_none()
items = user.items  # Works!
```

---

## Summary

**Key Patterns**:
- Use async engines and sessions for FastAPI
- Repository pattern for clean data access
- Alembic for schema migrations
- Connection pooling for production
- Eager loading to avoid N+1 queries
- Indexes on frequently queried columns
- Transactions for data consistency
- In-memory SQLite for testing

**Always**:
- Use `await` with database operations
- Close sessions properly (use dependency injection)
- Test database interactions

**Never**:
- Mix sync and async SQLAlchemy
- Use lazy loading with async
- Forget to commit transactions
- Hardcode database credentials
