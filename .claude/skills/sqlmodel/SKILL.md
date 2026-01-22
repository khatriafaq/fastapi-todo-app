---
name: sqlmodel
description: |
  Generate SQLModel implementations for FastAPI with PostgreSQL.
  Use when: creating database models, setting up SQLModel, implementing
  CRUD endpoints, handling relationships, or generating API schemas.
---

# SQLModel Skill

Generate type-safe database models and CRUD operations for FastAPI applications.

## Quick Reference

| Topic | Reference File | When to Use |
|-------|----------------|-------------|
| Models | [model-patterns.md](references/model-patterns.md) | Defining `table=True` models, fields, constraints |
| Relationships | [relationship-patterns.md](references/relationship-patterns.md) | 1:1, 1:N, N:N, self-referential |
| Schemas | [schema-patterns.md](references/schema-patterns.md) | API validation, Create/Read/Update patterns |
| Database | [database-setup.md](references/database-setup.md) | Engine, session, sync/async configuration |
| CRUD | [crud-patterns.md](references/crud-patterns.md) | Create, read, update, delete + routers |
| Anti-patterns | [anti-patterns.md](references/anti-patterns.md) | Common mistakes to avoid |

## Core Concepts

### table=True vs Plain SQLModel

```python
# DATABASE TABLE - has table=True
class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    email: str = Field(unique=True, index=True)
    name: str

# API SCHEMA - no table=True (validation only)
class UserCreate(SQLModel):
    email: str
    name: str
```

**Key distinction:**
- `table=True` → Creates database table, use for persistence
- No `table=True` → Pydantic model only, use for API validation

## Workflow

Follow this sequence when implementing SQLModel:

```
1. REQUIREMENTS     → Identify entities and relationships
2. MODELS           → Create table=True models (references/model-patterns.md)
3. RELATIONSHIPS    → Add foreign keys and Relationship() (references/relationship-patterns.md)
4. SCHEMAS          → Create/Read/Update schemas (references/schema-patterns.md)
5. DATABASE         → Configure engine and session (references/database-setup.md)
6. CRUD             → Implement operations and routers (references/crud-patterns.md)
```

## Relationship Decision Tree

```
Does entity A relate to entity B?
│
├─ One A → One B?
│  └─ Use One-to-One (uselist=False)
│
├─ One A → Many B?
│  └─ Use One-to-Many (list["B"] + back_populates)
│
├─ Many A → Many B?
│  │
│  └─ Need extra fields on relationship?
│     ├─ Yes → Use Association Object (link table with fields)
│     └─ No  → Use Many-to-Many (simple link table)
│
└─ A relates to itself?
   └─ Use Self-Referential (parent_id + Relationship)
```

## Minimal Working Example

```python
from sqlmodel import Field, Session, SQLModel, create_engine, select

# Model
class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
    done: bool = False

# Schemas
class TaskCreate(SQLModel):
    title: str

class TaskRead(SQLModel):
    id: int
    title: str
    done: bool

# Database
engine = create_engine("postgresql://user:pass@localhost/db")
SQLModel.metadata.create_all(engine)

def get_session():
    with Session(engine) as session:
        yield session

# CRUD
def create_task(session: Session, task: TaskCreate) -> Task:
    db_task = Task.model_validate(task)
    session.add(db_task)
    session.commit()
    session.refresh(db_task)
    return db_task

def get_tasks(session: Session) -> list[Task]:
    return session.exec(select(Task)).all()
```

## Output Checklist

Before delivering SQLModel code, verify:

- [ ] All table models have `table=True`
- [ ] Primary keys use `Field(default=None, primary_key=True)`
- [ ] Foreign keys match referenced table names (lowercase)
- [ ] `back_populates` values match on both sides of relationships
- [ ] Schemas don't have `table=True`
- [ ] Session is properly yielded in dependency
- [ ] `commit()` and `refresh()` called after mutations
- [ ] Appropriate indexes on frequently queried fields

## Common Patterns

### Timestamps

```python
from datetime import datetime, timezone

class TimestampMixin(SQLModel):
    created_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
    updated_at: datetime = Field(default_factory=lambda: datetime.now(timezone.utc))
```

### Soft Delete

```python
class SoftDeleteMixin(SQLModel):
    deleted_at: datetime | None = Field(default=None, index=True)

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None
```

### UUID Primary Keys

```python
from uuid import UUID, uuid4

class UUIDModel(SQLModel, table=True):
    id: UUID = Field(default_factory=uuid4, primary_key=True)
```

## Validation Script

Run validation on generated models:

```bash
python .claude/skills/sqlmodel/scripts/validate_models.py path/to/models.py
```

## See Also

- [SQLModel Documentation](https://sqlmodel.tiangolo.com/)
- [FastAPI with SQLModel](https://sqlmodel.tiangolo.com/tutorial/fastapi/)
- [SQLAlchemy 2.0](https://docs.sqlalchemy.org/en/20/) (underlying engine)
