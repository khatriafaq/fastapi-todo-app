# CRUD Patterns

Patterns for Create, Read, Update, Delete operations with SQLModel and FastAPI.

## Basic CRUD Operations

### Create

```python
from sqlmodel import Session

def create_task(session: Session, task_create: TaskCreate) -> Task:
    """Create a new task."""
    task = Task.model_validate(task_create)
    session.add(task)
    session.commit()
    session.refresh(task)  # Load generated fields (id, timestamps)
    return task
```

### Read Single

```python
def get_task(session: Session, task_id: int) -> Task | None:
    """Get task by ID."""
    return session.get(Task, task_id)
```

### Read Multiple

```python
from sqlmodel import select

def get_tasks(session: Session) -> list[Task]:
    """Get all tasks."""
    return session.exec(select(Task)).all()

def get_tasks_by_owner(session: Session, owner_id: int) -> list[Task]:
    """Get tasks filtered by owner."""
    statement = select(Task).where(Task.owner_id == owner_id)
    return session.exec(statement).all()
```

### Update

```python
def update_task(
    session: Session,
    task_id: int,
    task_update: TaskUpdate
) -> Task | None:
    """Update a task with partial data."""
    task = session.get(Task, task_id)
    if not task:
        return None

    # Only update fields that were sent
    update_data = task_update.model_dump(exclude_unset=True)
    task.sqlmodel_update(update_data)

    session.add(task)
    session.commit()
    session.refresh(task)
    return task
```

### Delete

```python
def delete_task(session: Session, task_id: int) -> bool:
    """Delete a task. Returns True if deleted."""
    task = session.get(Task, task_id)
    if not task:
        return False

    session.delete(task)
    session.commit()
    return True
```

## FastAPI Router Integration

### Basic Router

```python
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, status
from sqlmodel import Session, select

from app.database import get_session
from app.models import Task, TaskCreate, TaskRead, TaskUpdate

router = APIRouter(prefix="/tasks", tags=["tasks"])
SessionDep = Annotated[Session, Depends(get_session)]

@router.post("/", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(task: TaskCreate, session: SessionDep):
    db_task = Task.model_validate(task)
    session.add(db_task)
    session.commit()
    session.refresh(db_task)
    return db_task

@router.get("/", response_model=list[TaskRead])
def list_tasks(session: SessionDep):
    return session.exec(select(Task)).all()

@router.get("/{task_id}", response_model=TaskRead)
def get_task(task_id: int, session: SessionDep):
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task

@router.patch("/{task_id}", response_model=TaskRead)
def update_task(task_id: int, task_update: TaskUpdate, session: SessionDep):
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    update_data = task_update.model_dump(exclude_unset=True)
    task.sqlmodel_update(update_data)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task

@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, session: SessionDep):
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    session.delete(task)
    session.commit()
```

## Query Patterns

### Filtering

```python
from sqlmodel import select

# Single filter
def get_active_tasks(session: Session) -> list[Task]:
    statement = select(Task).where(Task.is_completed == False)
    return session.exec(statement).all()

# Multiple filters (AND)
def get_user_pending_tasks(session: Session, user_id: int) -> list[Task]:
    statement = select(Task).where(
        Task.owner_id == user_id,
        Task.is_completed == False
    )
    return session.exec(statement).all()

# OR filter
from sqlmodel import or_

def search_tasks(session: Session, query: str) -> list[Task]:
    statement = select(Task).where(
        or_(
            Task.title.contains(query),
            Task.description.contains(query)
        )
    )
    return session.exec(statement).all()
```

### Sorting

```python
# Ascending
def get_tasks_by_date(session: Session) -> list[Task]:
    statement = select(Task).order_by(Task.created_at)
    return session.exec(statement).all()

# Descending
def get_recent_tasks(session: Session) -> list[Task]:
    statement = select(Task).order_by(Task.created_at.desc())
    return session.exec(statement).all()

# Multiple columns
def get_tasks_sorted(session: Session) -> list[Task]:
    statement = select(Task).order_by(Task.priority.desc(), Task.created_at)
    return session.exec(statement).all()
```

### Pagination

```python
def get_tasks_paginated(
    session: Session,
    page: int = 1,
    page_size: int = 10
) -> list[Task]:
    offset = (page - 1) * page_size
    statement = select(Task).offset(offset).limit(page_size)
    return session.exec(statement).all()

# Cursor-based pagination (better for large datasets)
def get_tasks_after_cursor(
    session: Session,
    cursor_id: int | None = None,
    limit: int = 10
) -> list[Task]:
    statement = select(Task).order_by(Task.id).limit(limit)
    if cursor_id:
        statement = statement.where(Task.id > cursor_id)
    return session.exec(statement).all()
```

### Counting

```python
from sqlmodel import func, select

def count_tasks(session: Session) -> int:
    statement = select(func.count(Task.id))
    return session.exec(statement).one()

def count_user_tasks(session: Session, user_id: int) -> int:
    statement = select(func.count(Task.id)).where(Task.owner_id == user_id)
    return session.exec(statement).one()
```

## Relationship Loading

### Eager Loading (Avoid N+1)

```python
from sqlalchemy.orm import selectinload

def get_teams_with_heroes(session: Session) -> list[Team]:
    """Load teams with all heroes in one query."""
    statement = select(Team).options(selectinload(Team.heroes))
    return session.exec(statement).all()

# Multiple relationships
def get_posts_full(session: Session) -> list[Post]:
    statement = select(Post).options(
        selectinload(Post.author),
        selectinload(Post.comments),
        selectinload(Post.tags)
    )
    return session.exec(statement).all()
```

### Joined Loading

```python
from sqlalchemy.orm import joinedload

def get_hero_with_team(session: Session, hero_id: int) -> Hero | None:
    """Load hero with team in single JOIN."""
    statement = (
        select(Hero)
        .options(joinedload(Hero.team))
        .where(Hero.id == hero_id)
    )
    return session.exec(statement).first()
```

## Advanced Operations

### Bulk Create

```python
def create_tasks_bulk(session: Session, tasks: list[TaskCreate]) -> list[Task]:
    """Create multiple tasks efficiently."""
    db_tasks = [Task.model_validate(t) for t in tasks]
    session.add_all(db_tasks)
    session.commit()
    for task in db_tasks:
        session.refresh(task)
    return db_tasks
```

### Bulk Update

```python
from sqlmodel import update

def mark_tasks_completed(session: Session, task_ids: list[int]) -> int:
    """Mark multiple tasks as completed. Returns count updated."""
    statement = (
        update(Task)
        .where(Task.id.in_(task_ids))
        .values(is_completed=True)
    )
    result = session.exec(statement)
    session.commit()
    return result.rowcount
```

### Bulk Delete

```python
from sqlmodel import delete

def delete_completed_tasks(session: Session, user_id: int) -> int:
    """Delete all completed tasks for user. Returns count deleted."""
    statement = delete(Task).where(
        Task.owner_id == user_id,
        Task.is_completed == True
    )
    result = session.exec(statement)
    session.commit()
    return result.rowcount
```

### Upsert (Insert or Update)

```python
from sqlalchemy.dialects.postgresql import insert

def upsert_setting(session: Session, key: str, value: str) -> Setting:
    """Insert or update a setting."""
    statement = insert(Setting).values(key=key, value=value)
    statement = statement.on_conflict_do_update(
        index_elements=["key"],
        set_={"value": value}
    )
    session.exec(statement)
    session.commit()
    return session.exec(select(Setting).where(Setting.key == key)).first()
```

## Repository Pattern

### Generic Repository

```python
from typing import Generic, TypeVar, Type
from sqlmodel import SQLModel, Session, select

T = TypeVar("T", bound=SQLModel)

class Repository(Generic[T]):
    def __init__(self, model: Type[T], session: Session):
        self.model = model
        self.session = session

    def get(self, id: int) -> T | None:
        return self.session.get(self.model, id)

    def get_all(self) -> list[T]:
        return self.session.exec(select(self.model)).all()

    def create(self, data: SQLModel) -> T:
        obj = self.model.model_validate(data)
        self.session.add(obj)
        self.session.commit()
        self.session.refresh(obj)
        return obj

    def update(self, id: int, data: SQLModel) -> T | None:
        obj = self.get(id)
        if not obj:
            return None
        update_data = data.model_dump(exclude_unset=True)
        obj.sqlmodel_update(update_data)
        self.session.add(obj)
        self.session.commit()
        self.session.refresh(obj)
        return obj

    def delete(self, id: int) -> bool:
        obj = self.get(id)
        if not obj:
            return False
        self.session.delete(obj)
        self.session.commit()
        return True

# Usage
task_repo = Repository(Task, session)
task = task_repo.create(TaskCreate(title="New task"))
```

## Complete Router Example

```python
from typing import Annotated
from fastapi import APIRouter, Depends, HTTPException, Query, status
from sqlalchemy.orm import selectinload
from sqlmodel import Session, select, func

from app.database import get_session
from app.models import (
    Task, TaskCreate, TaskRead, TaskUpdate, TaskWithOwner,
    PaginatedResponse
)

router = APIRouter(prefix="/tasks", tags=["tasks"])
SessionDep = Annotated[Session, Depends(get_session)]

@router.post("/", response_model=TaskRead, status_code=status.HTTP_201_CREATED)
def create_task(task: TaskCreate, session: SessionDep):
    """Create a new task."""
    db_task = Task.model_validate(task)
    session.add(db_task)
    session.commit()
    session.refresh(db_task)
    return db_task

@router.get("/", response_model=PaginatedResponse[TaskRead])
def list_tasks(
    session: SessionDep,
    page: int = Query(1, ge=1),
    page_size: int = Query(10, ge=1, le=100),
    completed: bool | None = None
):
    """List tasks with pagination and optional filter."""
    # Build query
    query = select(Task)
    if completed is not None:
        query = query.where(Task.is_completed == completed)

    # Count total
    count_query = select(func.count(Task.id))
    if completed is not None:
        count_query = count_query.where(Task.is_completed == completed)
    total = session.exec(count_query).one()

    # Paginate
    offset = (page - 1) * page_size
    tasks = session.exec(query.offset(offset).limit(page_size)).all()

    return PaginatedResponse.create(
        items=tasks,
        total=total,
        page=page,
        page_size=page_size
    )

@router.get("/{task_id}", response_model=TaskWithOwner)
def get_task(task_id: int, session: SessionDep):
    """Get task with owner details."""
    statement = (
        select(Task)
        .options(selectinload(Task.owner))
        .where(Task.id == task_id)
    )
    task = session.exec(statement).first()
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    return task

@router.patch("/{task_id}", response_model=TaskRead)
def update_task(task_id: int, task_update: TaskUpdate, session: SessionDep):
    """Partially update a task."""
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")

    update_data = task_update.model_dump(exclude_unset=True)
    task.sqlmodel_update(update_data)
    session.add(task)
    session.commit()
    session.refresh(task)
    return task

@router.delete("/{task_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_task(task_id: int, session: SessionDep):
    """Delete a task."""
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    session.delete(task)
    session.commit()

@router.post("/{task_id}/complete", response_model=TaskRead)
def complete_task(task_id: int, session: SessionDep):
    """Mark task as completed."""
    task = session.get(Task, task_id)
    if not task:
        raise HTTPException(status_code=404, detail="Task not found")
    task.is_completed = True
    session.add(task)
    session.commit()
    session.refresh(task)
    return task
```
