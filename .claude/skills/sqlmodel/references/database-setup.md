# Database Setup

Patterns for configuring SQLModel database connections with PostgreSQL.

## Synchronous Setup

### Basic Configuration

```python
from sqlmodel import SQLModel, Session, create_engine

# Connection URL
DATABASE_URL = "postgresql://user:password@localhost:5432/dbname"

# Create engine
engine = create_engine(DATABASE_URL, echo=True)  # echo=True for SQL logging

def create_db_and_tables():
    """Create all tables defined in SQLModel metadata."""
    SQLModel.metadata.create_all(engine)

def get_session():
    """Dependency for FastAPI endpoints."""
    with Session(engine) as session:
        yield session
```

### FastAPI Integration

```python
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI
from sqlmodel import Session

@asynccontextmanager
async def lifespan(app: FastAPI):
    """Create tables on startup."""
    create_db_and_tables()
    yield

app = FastAPI(lifespan=lifespan)

@app.get("/tasks")
def list_tasks(session: Session = Depends(get_session)):
    return session.exec(select(Task)).all()
```

## Asynchronous Setup

### Async Engine and Session

```python
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from sqlmodel import SQLModel

# Async connection URL (note: asyncpg driver)
DATABASE_URL = "postgresql+asyncpg://user:password@localhost:5432/dbname"

# Create async engine
async_engine = create_async_engine(DATABASE_URL, echo=True)

# Async session factory
async_session = sessionmaker(
    async_engine,
    class_=AsyncSession,
    expire_on_commit=False
)

async def create_db_and_tables():
    """Create all tables asynchronously."""
    async with async_engine.begin() as conn:
        await conn.run_sync(SQLModel.metadata.create_all)

async def get_session():
    """Async dependency for FastAPI endpoints."""
    async with async_session() as session:
        yield session
```

### Async FastAPI Integration

```python
from contextlib import asynccontextmanager
from fastapi import Depends, FastAPI
from sqlalchemy.ext.asyncio import AsyncSession

@asynccontextmanager
async def lifespan(app: FastAPI):
    await create_db_and_tables()
    yield

app = FastAPI(lifespan=lifespan)

@app.get("/tasks")
async def list_tasks(session: AsyncSession = Depends(get_session)):
    result = await session.exec(select(Task))
    return result.all()
```

## Connection Pooling

### Sync Pool Configuration

```python
engine = create_engine(
    DATABASE_URL,
    pool_size=5,           # Number of persistent connections
    max_overflow=10,       # Extra connections allowed beyond pool_size
    pool_timeout=30,       # Seconds to wait for connection
    pool_recycle=1800,     # Recycle connections after 30 minutes
    pool_pre_ping=True,    # Check connection health before using
)
```

### Async Pool Configuration

```python
async_engine = create_async_engine(
    DATABASE_URL,
    pool_size=5,
    max_overflow=10,
    pool_timeout=30,
    pool_recycle=1800,
    pool_pre_ping=True,
)
```

## Environment-Based Configuration

### Using python-dotenv

```python
# config.py
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://localhost/dev")
DB_POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "5"))
DB_MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", "10"))
DB_ECHO = os.getenv("DB_ECHO", "false").lower() == "true"
```

```python
# database.py
from sqlmodel import create_engine
from config import DATABASE_URL, DB_POOL_SIZE, DB_MAX_OVERFLOW, DB_ECHO

engine = create_engine(
    DATABASE_URL,
    pool_size=DB_POOL_SIZE,
    max_overflow=DB_MAX_OVERFLOW,
    echo=DB_ECHO,
)
```

### Environment Variables

```bash
# .env
DATABASE_URL=postgresql://user:password@localhost:5432/myapp
DB_POOL_SIZE=10
DB_MAX_OVERFLOW=20
DB_ECHO=false
```

## Testing Configuration

### SQLite for Tests

```python
from sqlmodel import SQLModel, Session, create_engine

# In-memory SQLite for fast tests
TEST_DATABASE_URL = "sqlite://"  # In-memory
# Or file-based for debugging
# TEST_DATABASE_URL = "sqlite:///./test.db"

test_engine = create_engine(
    TEST_DATABASE_URL,
    connect_args={"check_same_thread": False}  # Required for SQLite
)

def get_test_session():
    """Test session with rollback."""
    with Session(test_engine) as session:
        yield session

# pytest fixture
import pytest

@pytest.fixture(name="session")
def session_fixture():
    SQLModel.metadata.create_all(test_engine)
    with Session(test_engine) as session:
        yield session
    SQLModel.metadata.drop_all(test_engine)
```

### PostgreSQL Test Container

```python
import pytest
from testcontainers.postgres import PostgresContainer
from sqlmodel import SQLModel, Session, create_engine

@pytest.fixture(scope="session")
def postgres_container():
    with PostgresContainer("postgres:15") as postgres:
        yield postgres

@pytest.fixture(scope="session")
def engine(postgres_container):
    engine = create_engine(postgres_container.get_connection_url())
    SQLModel.metadata.create_all(engine)
    return engine

@pytest.fixture
def session(engine):
    with Session(engine) as session:
        yield session
        session.rollback()
```

## Multiple Databases

### Read Replica Pattern

```python
from sqlmodel import Session, create_engine

# Primary for writes
primary_engine = create_engine("postgresql://user:pass@primary:5432/db")

# Replica for reads
replica_engine = create_engine("postgresql://user:pass@replica:5432/db")

def get_write_session():
    with Session(primary_engine) as session:
        yield session

def get_read_session():
    with Session(replica_engine) as session:
        yield session

# Usage
@app.post("/tasks")
def create_task(task: TaskCreate, session: Session = Depends(get_write_session)):
    ...

@app.get("/tasks")
def list_tasks(session: Session = Depends(get_read_session)):
    ...
```

## Transaction Management

### Explicit Transaction

```python
def transfer_funds(session: Session, from_id: int, to_id: int, amount: float):
    """Explicit transaction with rollback on error."""
    try:
        from_account = session.get(Account, from_id)
        to_account = session.get(Account, to_id)

        from_account.balance -= amount
        to_account.balance += amount

        session.add(from_account)
        session.add(to_account)
        session.commit()
    except Exception:
        session.rollback()
        raise
```

### Nested Transactions (Savepoints)

```python
def complex_operation(session: Session):
    # Outer transaction
    user = User(name="John")
    session.add(user)

    # Savepoint
    savepoint = session.begin_nested()
    try:
        task = Task(title="Test", owner_id=user.id)
        session.add(task)
        savepoint.commit()
    except Exception:
        savepoint.rollback()
        # User creation still intact

    session.commit()
```

## Health Check

```python
from sqlalchemy import text

def check_database_health(session: Session) -> bool:
    """Check if database is reachable."""
    try:
        session.exec(text("SELECT 1"))
        return True
    except Exception:
        return False

@app.get("/health")
def health_check(session: Session = Depends(get_session)):
    if check_database_health(session):
        return {"status": "healthy", "database": "connected"}
    return {"status": "unhealthy", "database": "disconnected"}
```

## Complete Setup Example

```python
# config.py
import os
from dotenv import load_dotenv

load_dotenv()

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://user:pass@localhost:5432/myapp")
DB_POOL_SIZE = int(os.getenv("DB_POOL_SIZE", "5"))
DB_MAX_OVERFLOW = int(os.getenv("DB_MAX_OVERFLOW", "10"))
DB_ECHO = os.getenv("DB_ECHO", "false").lower() == "true"
```

```python
# database.py
from typing import Annotated

from fastapi import Depends
from sqlmodel import Session, SQLModel, create_engine

from config import DATABASE_URL, DB_POOL_SIZE, DB_MAX_OVERFLOW, DB_ECHO

engine = create_engine(
    DATABASE_URL,
    pool_size=DB_POOL_SIZE,
    max_overflow=DB_MAX_OVERFLOW,
    echo=DB_ECHO,
    pool_pre_ping=True,
)

def create_db_and_tables():
    SQLModel.metadata.create_all(engine)

def get_session():
    with Session(engine) as session:
        yield session

# Type alias for dependency injection
SessionDep = Annotated[Session, Depends(get_session)]
```

```python
# main.py
from contextlib import asynccontextmanager
from fastapi import FastAPI
from database import create_db_and_tables, SessionDep

@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield

app = FastAPI(lifespan=lifespan)

@app.get("/tasks")
def list_tasks(session: SessionDep):
    return session.exec(select(Task)).all()
```

## Migrations with Alembic

### Setup

```bash
pip install alembic
alembic init alembic
```

### Configure env.py

```python
# alembic/env.py
from sqlmodel import SQLModel
from app.models import *  # Import all models
from app.database import DATABASE_URL

config.set_main_option("sqlalchemy.url", DATABASE_URL)
target_metadata = SQLModel.metadata
```

### Generate Migration

```bash
alembic revision --autogenerate -m "Add task table"
alembic upgrade head
```
