# Anti-Patterns

Common mistakes to avoid when using SQLModel.

## Missing table=True

**Problem:** Model doesn't create a database table.

```python
# WRONG - No table created
class Task(SQLModel):
    id: int | None = Field(default=None, primary_key=True)
    title: str

# CORRECT - Creates table
class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
```

**Symptoms:** No errors during model definition, but queries fail with "table not found".

## Schema with table=True

**Problem:** Validation schema creates unnecessary table.

```python
# WRONG - Creates table you don't want
class TaskCreate(SQLModel, table=True):
    title: str

# CORRECT - No table, just validation
class TaskCreate(SQLModel):
    title: str
```

## N+1 Query Problem

**Problem:** Loading related objects triggers separate query for each.

```python
# WRONG - N+1 queries
def get_teams_bad(session: Session) -> list[Team]:
    teams = session.exec(select(Team)).all()
    for team in teams:
        print(team.heroes)  # Each access = new query!
    return teams

# CORRECT - Single query with eager loading
from sqlalchemy.orm import selectinload

def get_teams_good(session: Session) -> list[Team]:
    statement = select(Team).options(selectinload(Team.heroes))
    teams = session.exec(statement).all()
    return teams
```

## Mismatched back_populates

**Problem:** Relationship names don't match, causing silent failures.

```python
# WRONG - Mismatched names
class Team(SQLModel, table=True):
    heroes: list["Hero"] = Relationship(back_populates="team")

class Hero(SQLModel, table=True):
    team_id: int | None = Field(foreign_key="team.id")
    my_team: Team | None = Relationship(back_populates="heroes")  # Wrong name!

# CORRECT - Names match exactly
class Team(SQLModel, table=True):
    heroes: list["Hero"] = Relationship(back_populates="team")

class Hero(SQLModel, table=True):
    team_id: int | None = Field(foreign_key="team.id")
    team: Team | None = Relationship(back_populates="heroes")  # Matches "team"
```

## Wrong Foreign Key Table Name

**Problem:** Foreign key references wrong table name.

```python
# WRONG - Table name is lowercase, not class name
class Hero(SQLModel, table=True):
    team_id: int = Field(foreign_key="Team.id")  # Wrong!

# CORRECT - Use actual table name (lowercase by default)
class Hero(SQLModel, table=True):
    team_id: int = Field(foreign_key="team.id")  # Correct
```

## Missing refresh() After Commit

**Problem:** Object doesn't have generated values after commit.

```python
# WRONG - id is still None
def create_task_bad(session: Session, task: TaskCreate) -> Task:
    db_task = Task.model_validate(task)
    session.add(db_task)
    session.commit()
    return db_task  # db_task.id is None!

# CORRECT - refresh loads generated values
def create_task_good(session: Session, task: TaskCreate) -> Task:
    db_task = Task.model_validate(task)
    session.add(db_task)
    session.commit()
    session.refresh(db_task)  # Now db_task.id is populated
    return db_task
```

## Session Not Yielded in Dependency

**Problem:** Session isn't properly closed.

```python
# WRONG - Session never closes
def get_session_bad():
    return Session(engine)

# CORRECT - Session properly closes via yield
def get_session_good():
    with Session(engine) as session:
        yield session
```

## Circular Import with Relationships

**Problem:** Models importing each other causes ImportError.

```python
# WRONG - models/team.py and models/hero.py import each other
# team.py
from models.hero import Hero
class Team(SQLModel, table=True):
    heroes: list[Hero] = Relationship()

# hero.py
from models.team import Team  # Circular import!
class Hero(SQLModel, table=True):
    team: Team = Relationship()

# CORRECT - Use string references
# team.py (no import needed)
class Team(SQLModel, table=True):
    heroes: list["Hero"] = Relationship(back_populates="team")

# hero.py
class Hero(SQLModel, table=True):
    team: "Team" = Relationship(back_populates="heroes")

# models/__init__.py - import all to resolve references
from models.team import Team
from models.hero import Hero
```

## Not Handling None in Optional Relationships

**Problem:** Accessing optional relationship without null check.

```python
# WRONG - Will raise AttributeError if team is None
def get_team_name(hero: Hero) -> str:
    return hero.team.name  # Fails if hero.team is None

# CORRECT - Handle None case
def get_team_name(hero: Hero) -> str | None:
    return hero.team.name if hero.team else None
```

## Using model_dump() Without exclude_unset for Updates

**Problem:** Unset fields overwrite existing values with None.

```python
# WRONG - All None fields overwrite existing data
def update_task_bad(session: Session, task_id: int, update: TaskUpdate):
    task = session.get(Task, task_id)
    task.sqlmodel_update(update.model_dump())  # Overwrites with None!
    session.commit()

# CORRECT - Only update fields that were sent
def update_task_good(session: Session, task_id: int, update: TaskUpdate):
    task = session.get(Task, task_id)
    task.sqlmodel_update(update.model_dump(exclude_unset=True))
    session.commit()
```

## Creating Session Per Request Without Context Manager

**Problem:** Session stays open if exception occurs.

```python
# WRONG - Session may leak on exception
@app.get("/tasks")
def get_tasks_bad():
    session = Session(engine)
    tasks = session.exec(select(Task)).all()
    session.close()  # Never reached if exception!
    return tasks

# CORRECT - Context manager ensures cleanup
@app.get("/tasks")
def get_tasks_good(session: Session = Depends(get_session)):
    return session.exec(select(Task)).all()
```

## Committing Inside Loop

**Problem:** Inefficient, slow operations with many commits.

```python
# WRONG - One commit per task
def create_tasks_bad(session: Session, tasks: list[TaskCreate]):
    for task in tasks:
        db_task = Task.model_validate(task)
        session.add(db_task)
        session.commit()  # Slow!

# CORRECT - Single commit at the end
def create_tasks_good(session: Session, tasks: list[TaskCreate]):
    for task in tasks:
        db_task = Task.model_validate(task)
        session.add(db_task)
    session.commit()  # One commit for all
```

## Using SQLite Features with PostgreSQL

**Problem:** SQLite-specific syntax fails on PostgreSQL.

```python
# WRONG - SQLite syntax
statement = text("SELECT * FROM task WHERE id = ?")

# CORRECT - PostgreSQL syntax
statement = text("SELECT * FROM task WHERE id = :id")
session.exec(statement, {"id": task_id})

# BEST - Use SQLModel/SQLAlchemy constructs
statement = select(Task).where(Task.id == task_id)
```

## Checklist

Before deploying SQLModel code, verify:

- [ ] All table models have `table=True`
- [ ] All schemas do NOT have `table=True`
- [ ] Foreign keys use lowercase table names
- [ ] `back_populates` matches on both relationship sides
- [ ] `refresh()` called after `commit()` when returning created objects
- [ ] Session is yielded in dependency function
- [ ] String references (`"Model"`) used for forward references
- [ ] `exclude_unset=True` used for partial updates
- [ ] Eager loading used for relationships accessed in loops
