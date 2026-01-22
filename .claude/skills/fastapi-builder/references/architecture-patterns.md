# FastAPI Architecture Patterns

This document describes proven project structures for FastAPI applications at different scales.

## Pattern Selection Guide

| Scale | Pattern | When to Use |
|-------|---------|-------------|
| Prototype | Single File | <100 lines, 1-3 endpoints, learning |
| Small Project | File-Type | Microservice, <10 endpoints, single domain |
| Medium Project | Module-Functionality | Multiple domains, 10+ endpoints, growing team |
| Large/Complex | Hexagonal | Complex business logic, high testability needs |

---

## 1. Single File (Level 1)

**Use for**: Quick prototypes, tutorials, minimal APIs

```
project/
├── main.py
└── requirements.txt
```

**main.py example**:
```python
from fastapi import FastAPI

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "Hello World"}

@app.get("/items/{item_id}")
def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "q": q}
```

**When to upgrade**: When you add a database, authentication, or exceed 3-4 endpoints.

---

## 2. File-Type Structure (Levels 2-3)

**Use for**: Microservices, small-to-medium APIs, single domain

Organizes code by technical layer (routers, models, schemas).

```
project/
├── app/
│   ├── __init__.py
│   ├── main.py              # FastAPI app instance, startup/shutdown
│   ├── config.py            # Settings (Pydantic BaseSettings)
│   ├── database.py          # Database connection, session
│   ├── dependencies.py      # Shared dependencies (auth, db session)
│   ├── models/              # SQLAlchemy models
│   │   ├── __init__.py
│   │   ├── user.py
│   │   └── item.py
│   ├── schemas/             # Pydantic schemas (request/response)
│   │   ├── __init__.py
│   │   ├── user.py
│   │   └── item.py
│   ├── crud/                # Database operations
│   │   ├── __init__.py
│   │   ├── user.py
│   │   └── item.py
│   └── routers/             # API endpoints
│       ├── __init__.py
│       ├── users.py
│       └── items.py
├── alembic/                 # Database migrations
├── tests/
├── .env
├── requirements.txt
└── README.md
```

**Key files**:

**app/main.py**:
```python
from fastapi import FastAPI
from .routers import users, items
from .database import engine
from . import models

models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="My API")

app.include_router(users.router)
app.include_router(items.router)
```

**app/database.py**:
```python
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from .config import settings

engine = create_engine(settings.database_url)
SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)
Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
```

**Pros**: Clear technical separation, easy to navigate for small teams.

**Cons**: Related code scattered across directories (e.g., user logic split across models/user.py, schemas/user.py, crud/user.py, routers/users.py).

**When to upgrade**: When you have multiple business domains (users, products, orders, billing) and find yourself jumping between many files.

---

## 3. Module-Functionality Structure (Level 4)

**Use for**: Monoliths, multiple domains, scaling teams

Organizes code by business capability (feature modules).

```
project/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── core/                # Shared infrastructure
│   │   ├── __init__.py
│   │   ├── config.py
│   │   ├── security.py      # JWT, password hashing
│   │   ├── database.py
│   │   └── dependencies.py
│   ├── modules/             # Business modules
│   │   ├── users/
│   │   │   ├── __init__.py
│   │   │   ├── router.py
│   │   │   ├── models.py
│   │   │   ├── schemas.py
│   │   │   ├── service.py   # Business logic
│   │   │   └── repository.py # Data access
│   │   ├── items/
│   │   │   ├── __init__.py
│   │   │   ├── router.py
│   │   │   ├── models.py
│   │   │   ├── schemas.py
│   │   │   ├── service.py
│   │   │   └── repository.py
│   │   └── auth/
│   │       ├── __init__.py
│   │       ├── router.py
│   │       ├── schemas.py
│   │       └── service.py
│   ├── middleware/          # Custom middleware
│   │   ├── __init__.py
│   │   ├── logging.py
│   │   └── error_handler.py
│   └── utils/               # Shared utilities
│       └── __init__.py
├── alembic/
├── tests/
│   ├── test_users/
│   └── test_items/
├── .env
├── docker-compose.yml
├── Dockerfile
├── requirements.txt
└── README.md
```

**Key pattern**:
Each module contains ALL related code for a business capability:
- `router.py` - API endpoints
- `models.py` - Database models
- `schemas.py` - Request/response validation
- `service.py` - Business logic
- `repository.py` - Data access layer

**app/main.py**:
```python
from fastapi import FastAPI
from .modules.users.router import router as users_router
from .modules.items.router import router as items_router
from .modules.auth.router import router as auth_router
from .middleware import error_handler, logging
from .core.database import engine, Base

Base.metadata.create_all(bind=engine)

app = FastAPI(title="My API")

# Middleware
app.add_middleware(logging.LoggingMiddleware)
app.add_exception_handler(Exception, error_handler.global_exception_handler)

# Routers
app.include_router(auth_router, prefix="/auth", tags=["auth"])
app.include_router(users_router, prefix="/users", tags=["users"])
app.include_router(items_router, prefix="/items", tags=["items"])
```

**Module example (modules/users/service.py)**:
```python
from sqlalchemy.orm import Session
from . import models, schemas
from .repository import UserRepository
from app.core.security import get_password_hash, verify_password

class UserService:
    def __init__(self, db: Session):
        self.repo = UserRepository(db)

    def create_user(self, user: schemas.UserCreate) -> models.User:
        hashed_password = get_password_hash(user.password)
        db_user = models.User(email=user.email, hashed_password=hashed_password)
        return self.repo.create(db_user)

    def authenticate(self, email: str, password: str) -> models.User | None:
        user = self.repo.get_by_email(email)
        if user and verify_password(password, user.hashed_password):
            return user
        return None
```

**Pros**:
- All code for a feature in one place
- Easy to understand and maintain large codebases
- Team can own specific modules
- Clear dependency boundaries

**Cons**:
- More boilerplate
- Requires discipline to avoid circular dependencies

---

## 4. Hexagonal Architecture (Level 5)

**Use for**: Complex business logic, high testability, swappable infrastructure

Also called "Ports and Adapters" - separates business logic from infrastructure.

```
project/
├── app/
│   ├── __init__.py
│   ├── main.py
│   ├── domain/              # Business entities (no dependencies)
│   │   ├── __init__.py
│   │   ├── user.py          # Domain models (pure Python)
│   │   └── exceptions.py
│   ├── application/         # Use cases (business logic)
│   │   ├── __init__.py
│   │   ├── ports/           # Interfaces
│   │   │   ├── user_repository.py  # Abstract repository
│   │   │   └── email_service.py
│   │   └── services/
│   │       └── user_service.py
│   ├── infrastructure/      # External implementations
│   │   ├── __init__.py
│   │   ├── database/
│   │   │   ├── sqlalchemy_user_repository.py  # Concrete implementation
│   │   │   └── models.py    # SQLAlchemy models
│   │   ├── email/
│   │   │   └── smtp_email_service.py
│   │   └── config.py
│   └── presentation/        # API layer
│       ├── __init__.py
│       ├── api/
│       │   └── v1/
│       │       └── users.py
│       └── schemas/
│           └── user.py
├── tests/
│   ├── unit/               # Test domain/application (fast)
│   └── integration/        # Test infrastructure (slower)
├── requirements.txt
└── README.md
```

**Key concepts**:
- **Domain**: Pure business logic, no framework dependencies
- **Application**: Use cases, depends on domain and port interfaces
- **Infrastructure**: Implements ports (database, email, external APIs)
- **Presentation**: HTTP layer (FastAPI routers, schemas)

**Dependency rule**: Domain ← Application ← Infrastructure/Presentation

**Example port (application/ports/user_repository.py)**:
```python
from abc import ABC, abstractmethod
from app.domain.user import User

class UserRepository(ABC):
    @abstractmethod
    def get_by_id(self, user_id: int) -> User | None:
        pass

    @abstractmethod
    def create(self, user: User) -> User:
        pass
```

**Example adapter (infrastructure/database/sqlalchemy_user_repository.py)**:
```python
from sqlalchemy.orm import Session
from app.application.ports.user_repository import UserRepository
from app.domain.user import User
from .models import UserModel

class SQLAlchemyUserRepository(UserRepository):
    def __init__(self, db: Session):
        self.db = db

    def get_by_id(self, user_id: int) -> User | None:
        db_user = self.db.query(UserModel).filter(UserModel.id == user_id).first()
        if db_user:
            return User(id=db_user.id, email=db_user.email, ...)
        return None

    def create(self, user: User) -> User:
        db_user = UserModel(email=user.email, ...)
        self.db.add(db_user)
        self.db.commit()
        self.db.refresh(db_user)
        return User(id=db_user.id, email=db_user.email, ...)
```

**Pros**:
- Highly testable (mock ports in tests)
- Business logic independent of frameworks
- Easy to swap infrastructure (change database, email provider)

**Cons**:
- Significant boilerplate
- Complexity overhead for simple CRUD apps
- Requires strong architectural discipline

**When to use**:
- Complex business rules that need thorough testing
- Multiple infrastructure implementations (e.g., SQL + NoSQL)
- Long-lived projects where framework might change

---

## Async Architecture Considerations

**For async FastAPI (recommended for production)**:

**database.py with async support**:
```python
from sqlalchemy.ext.asyncio import AsyncSession, create_async_engine
from sqlalchemy.orm import sessionmaker
from .config import settings

engine = create_async_engine(settings.async_database_url)
AsyncSessionLocal = sessionmaker(
    engine, class_=AsyncSession, expire_on_commit=False
)

async def get_db():
    async with AsyncSessionLocal() as session:
        yield session
```

**Async router example**:
```python
from fastapi import APIRouter, Depends
from sqlalchemy.ext.asyncio import AsyncSession
from ..database import get_db

router = APIRouter()

@router.get("/users/{user_id}")
async def get_user(user_id: int, db: AsyncSession = Depends(get_db)):
    result = await db.execute(select(User).filter(User.id == user_id))
    user = result.scalar_one_or_none()
    return user
```

---

## Migration Path

**From Single File → File-Type**:
1. Create directory structure
2. Move models to `models/`
3. Create schemas in `schemas/`
4. Extract CRUD to `crud/`
5. Move endpoints to `routers/`
6. Update imports

**From File-Type → Module-Functionality**:
1. Create `modules/` directory
2. For each domain (users, items):
   - Create module directory
   - Move related files into module
   - Add `service.py` for business logic
   - Add `repository.py` for data access
3. Create `core/` for shared code
4. Update imports and router registration

---

## Summary

- **Level 1**: Single file
- **Level 2-3**: File-type structure
- **Level 4**: Module-functionality structure
- **Level 5**: Hexagonal architecture (if complexity warrants)

Choose based on current needs, not future speculation. Start simple, refactor when pain points emerge.
