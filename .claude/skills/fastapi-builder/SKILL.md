---
name: fastapi-builder
description: |
  Build FastAPI projects from hello world to production-ready applications.
  This skill should be used when users ask to create FastAPI applications, REST APIs,
  microservices, or full-stack backends. Supports progressive complexity levels:
  beginner tutorials, CRUD APIs, authentication systems, database integration,
  ML/AI endpoints, and enterprise-grade deployments with security best practices.
---

# FastAPI Builder

Build FastAPI applications with embedded best practices, from simple tutorials to production-ready systems.

## What This Skill Does

- Creates FastAPI projects at any complexity level (hello world → production)
- Implements REST APIs, microservices, full-stack backends, and ML/AI endpoints
- Applies security best practices and performance patterns automatically
- Structures projects for scalability using proven architectural patterns
- Integrates databases (PostgreSQL, SQLite, MongoDB) with proper async patterns
- Sets up authentication, authorization, and CORS configuration
- Configures deployment-ready containerization and health checks

## What This Skill Does NOT Do

- Deploy to cloud platforms (provides deployment-ready configs)
- Manage existing production databases (creates schema/migrations)
- Replace domain-specific API design decisions (guides implementation)

---

## Before Implementation

Gather context to ensure successful implementation:

| Source | Gather |
|--------|--------|
| **Codebase** | Existing FastAPI structure, dependencies, patterns, database models |
| **Conversation** | User's requirements: project type, features, complexity level, constraints |
| **Skill References** | Best practices from `references/` (security, architecture, anti-patterns) |
| **User Guidelines** | Team conventions, coding standards, deployment targets |

### Required Clarifications
1. What complexity level do you need? (1: Hello World, 2: CRUD, 3: Auth, 4: Production, 5: Advanced)
2. Is this a new project or adding features to an existing one?
3. What is the main purpose/domain of the API? (e.g., e-commerce, blog, task management)

### Optional Clarifications
4. Which database? (PostgreSQL recommended, or SQLite/MongoDB)
5. Authentication method? (JWT recommended, or OAuth2/API keys)
6. Deployment target? (Docker, cloud platform, local only)
7. Any specific requirements? (real-time, ML models, background tasks)

*Note: Infer answers from codebase context when possible. Only ask questions that cannot be determined from existing files or conversation.*

**IMPORTANT**: Ensure all required context is gathered before implementing.
Only ask user for THEIR specific requirements (domain expertise is in this skill).

---

## Progressive Complexity Levels

Determine the appropriate level based on user's request or current project state:

| Level | Indicators | What to Build |
|-------|-----------|---------------|
| **1. Hello World** | "first FastAPI app", "getting started", "tutorial" | Single file, 1-3 endpoints, no database |
| **2. Basic CRUD** | "simple API", "CRUD operations", specific data model | Structured app, SQLAlchemy models, basic validation |
| **3. Authentication** | "login", "users", "auth", "JWT", "sessions" | User management, JWT/OAuth2, protected routes |
| **4. Production API** | "production", "deployment", "scalable", "professional" | Layered architecture, async DB, middleware, Docker |
| **5. Advanced Features** | "microservices", "ML model", "real-time", "complex" | Multiple services, background tasks, WebSockets, ML integration |

**Default**: If unclear, ask user which level or start at Level 2 (Basic CRUD).

---

## Implementation Workflow

### Step 1: Determine Project Type & Level

Ask if not clear from conversation:
- **Complexity level** (1-5 above)
- **Project type**: New project vs. adding features to existing
- **Key features**: Authentication? Database? ML models? Real-time?

### Step 2: Choose Architecture Pattern

| Pattern | When to Use |
|---------|-------------|
| **Single File** | Level 1 (Hello World), quick prototypes |
| **File-Type Structure** | Levels 2-3, microservices, <10 endpoints |
| **Module-Functionality** | Levels 4-5, monoliths, multiple domains |
| **Hexagonal** | Level 5, complex business logic, testability critical |

See `references/architecture-patterns.md` for detailed structures.

### Step 3: Gather Requirements

Before writing code, clarify:

**Database**:
- Schema requirements (models, relationships)
- Migration strategy (Alembic recommended)
- Connection pooling needs

**Security** (Level 3+):
- Authentication method (JWT, OAuth2, API keys)
- Authorization rules (role-based, permission-based)
- CORS requirements

**Deployment** (Level 4+):
- Container requirements (Docker)
- Health check endpoints
- Environment configuration

### Step 4: Initialize Project

Use appropriate script from `scripts/`:

```bash
# New project
bash scripts/init-project.sh --name <project_name> --level <1-5> --db <postgres|sqlite|mongodb>

# Add feature to existing
# (detect existing structure and integrate)
```

Or implement manually following architecture pattern.

### Step 5: Implement Core Components

Build in this order to ensure dependencies are satisfied:

**Level 1: Hello World**
1. Single `main.py` with app instance
2. 1-3 endpoint functions
3. Run instructions

**Level 2: Basic CRUD**
1. Project structure (routers/, models/, schemas/)
2. Database models (SQLAlchemy)
3. Pydantic schemas (request/response validation)
4. CRUD operations
5. Router endpoints
6. Main app with router registration

**Level 3: Authentication**
1. All Level 2 components
2. User model with hashed passwords
3. JWT/OAuth2 utilities
4. Auth router (login, register, me)
5. Dependency for protected routes
6. Update existing routes with auth

**Level 4: Production API**
1. All Level 3 components
2. Layered architecture (api/, services/, repositories/)
3. Async database sessions
4. Middleware (CORS, logging, error handling)
5. Configuration management (Pydantic Settings)
6. Docker configuration
7. Health check endpoints

**Level 5: Advanced Features**
1. All Level 4 components
2. Background tasks (Celery/FastAPI BackgroundTasks)
3. WebSockets (if real-time needed)
4. ML model integration (if AI/ML)
5. Multiple services coordination
6. Advanced caching (Redis)
7. API versioning

### Step 6: Apply Security Best Practices

**ALWAYS include** (Level 2+):
- Input validation via Pydantic schemas
- Parameterized queries (ORM handles this)
- Environment-based configuration (never hardcode secrets)

**Level 3+**:
- Password hashing (bcrypt/passlib)
- JWT with expiration
- HTTPS enforcement (production)
- Rate limiting (production)

**Level 4+**:
- CORS with explicit origins (not `["*"]`)
- Disable debug mode in production
- Disable /docs in production (or protect with auth)
- Security headers middleware
- Dependency vulnerability scanning

See `references/security-best-practices.md` for complete checklist.

### Step 7: Optimize Performance

**Async Best Practices**:
- Use `async def` ONLY with async I/O operations
- Use sync `def` for CPU-bound or sync I/O operations
- Never block event loop in async routes

**Database**:
- Use async database drivers (asyncpg, motor)
- Connection pooling configuration
- Index frequently queried fields
- Eager/lazy loading strategy

See `references/performance-patterns.md` for optimization guide.

### Step 8: Add Testing (Level 2+)

**Test Structure**:
```
tests/
├── conftest.py          # Fixtures, test database setup
├── test_main.py         # App-level tests
├── test_routers/        # Router-specific tests
│   └── test_items.py
└── test_services/       # Business logic tests (Level 4+)
```

**Testing Pattern**:
```python
# tests/conftest.py
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.database import get_db, Base

SQLALCHEMY_DATABASE_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_DATABASE_URL)
TestingSessionLocal = sessionmaker(bind=engine)

@pytest.fixture
def db():
    Base.metadata.create_all(bind=engine)
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()
        Base.metadata.drop_all(bind=engine)

@pytest.fixture
def client(db):
    def override_get_db():
        yield db
    app.dependency_overrides[get_db] = override_get_db
    yield TestClient(app)
    app.dependency_overrides.clear()
```

**Run tests**: `pytest -v` or `pytest --cov=app`

### Step 9: Handle Edge Cases

**Common Edge Cases to Address**:

| Edge Case | How to Handle |
|-----------|---------------|
| Empty database | Return empty list `[]`, not error |
| Resource not found | Raise `HTTPException(404)` with clear message |
| Duplicate entry | Catch `IntegrityError`, return 409 Conflict |
| Invalid input | Pydantic validates automatically, customize error messages |
| Database connection failure | Use try/except, return 503 Service Unavailable |
| Token expired | Return 401 with "Token expired" message |
| Unauthorized access | Return 403 Forbidden (not 401) |
| Large file uploads | Set limits in middleware, return 413 |
| Rate limit exceeded | Return 429 Too Many Requests |

**Error Response Pattern**:
```python
from fastapi import HTTPException

# Consistent error responses
raise HTTPException(
    status_code=404,
    detail={"message": "Item not found", "item_id": item_id}
)
```

### Step 10: Provide Next Steps

After implementation, guide user:
1. How to run the application
2. How to run tests (`pytest -v`)
3. How to test endpoints (example curl/httpx commands)
4. Where to view auto-generated docs (`/docs`, `/redoc`)
5. Next features to add (based on current level)

---

## Decision Tree: Project Type

### New Project
```
Is it a learning exercise?
├─ YES → Level 1 (Hello World) or Level 2 (Basic CRUD)
└─ NO → Production-focused?
    ├─ YES → Start Level 4 (Production API)
    └─ NO → Level 2 or 3
```

### Existing Project
```
Detect current structure:
├─ Single file → Adding features? → Level 2 (restructure)
├─ File-type structure → Large codebase? → Level 4 (refactor to module-functionality)
└─ Module-functionality → Add feature in existing pattern
```

### Feature Addition
```
What feature?
├─ New endpoint → Add to appropriate router
├─ Authentication → Implement Level 3 patterns
├─ Database model → Add model, schema, CRUD, router
├─ Background task → Add task queue (Celery or BackgroundTasks)
└─ ML endpoint → Add ML integration patterns
```

---

## Common Patterns

### Endpoint Pattern (Level 2+)

```python
# Router file (routers/items.py)
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from .. import schemas, crud
from ..database import get_db

router = APIRouter(prefix="/items", tags=["items"])

@router.get("/", response_model=list[schemas.Item])
def get_items(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    return crud.get_items(db, skip=skip, limit=limit)

@router.post("/", response_model=schemas.Item, status_code=201)
def create_item(item: schemas.ItemCreate, db: Session = Depends(get_db)):
    return crud.create_item(db, item)
```

### Authentication Dependency (Level 3+)

```python
# dependencies/auth.py
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="token")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    # JWT validation logic
    # Return user or raise HTTPException
    pass
```

### Configuration Management (Level 3+)

```python
# config.py
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str
    secret_key: str
    algorithm: str = "HS256"

    class Config:
        env_file = ".env"

settings = Settings()
```

---

## Anti-Patterns to Avoid

**NEVER do these** (see `references/anti-patterns.md` for details):

1. **Blocking async routes**: Calling sync I/O in `async def` functions
2. **Hardcoded secrets**: API keys, passwords in code
3. **Missing error handling**: No try/except around external calls
4. **Wildcard CORS**: `allow_origins=["*"]` in production
5. **No input validation**: Trusting user input without Pydantic
6. **Sync database with async app**: Using sync SQLAlchemy without proper configuration
7. **Global state**: Mutable global variables
8. **Missing dependencies**: Not using Depends() for shared resources

---

## Quick Reference

| Need | See |
|------|-----|
| Project structures | `references/architecture-patterns.md` |
| Security checklist | `references/security-best-practices.md` |
| Database patterns | `references/database-patterns.md` |
| Performance tuning | `references/performance-patterns.md` |
| Common mistakes | `references/anti-patterns.md` |
| Deployment guide | `references/deployment-guide.md` |
| Example projects | `assets/templates/` |

## Official Documentation

For complex cases or latest updates, refer to official documentation:

| Resource | URL | Use For |
|----------|-----|---------|
| FastAPI Docs | https://fastapi.tiangolo.com/ | Core framework, tutorials |
| Pydantic v2 | https://docs.pydantic.dev/latest/ | Schema validation, settings |
| SQLAlchemy 2.0 | https://docs.sqlalchemy.org/en/20/ | Database ORM patterns |
| Starlette | https://www.starlette.io/ | Middleware, background tasks |
| python-jose | https://python-jose.readthedocs.io/ | JWT implementation |
| Alembic | https://alembic.sqlalchemy.org/ | Database migrations |

---

## Validation Checklist

Before delivering implementation, verify:

**Structure**:
- [ ] Appropriate architecture for complexity level
- [ ] Clear separation of concerns (routes, models, schemas, business logic)
- [ ] Consistent naming conventions

**Security**:
- [ ] No hardcoded secrets
- [ ] Input validation via Pydantic
- [ ] Authentication implemented correctly (if Level 3+)
- [ ] CORS configured appropriately
- [ ] SQL injection prevention (ORM usage)

**Performance**:
- [ ] Async/await used correctly (not blocking event loop)
- [ ] Database connections properly managed
- [ ] No N+1 query problems

**Production Readiness** (Level 4+):
- [ ] Environment-based configuration
- [ ] Health check endpoints
- [ ] Proper error handling and logging
- [ ] Docker configuration (if requested)
- [ ] Dependencies documented (requirements.txt/pyproject.toml)

**Testing** (Level 2+):
- [ ] Test file structure created
- [ ] Test fixtures for database isolation
- [ ] Tests for happy path scenarios
- [ ] Tests for error cases (404, 401, 422)
- [ ] Test coverage > 70% (Level 4+)

**Documentation**:
- [ ] Clear docstrings on complex functions
- [ ] README with setup/run instructions
- [ ] Example API calls or test commands
