# Model Patterns

Patterns for defining SQLModel database tables with `table=True`.

## Basic Model

```python
from sqlmodel import Field, SQLModel

class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
    description: str | None = Field(default=None)
    priority: int = Field(default=0)
```

**Key points:**
- `table=True` creates the database table
- Primary key uses `int | None` with `default=None` (auto-generated)
- Optional fields use `| None` with `Field(default=None)`
- Required fields have no default

## Field Types

### String Fields

```python
class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)

    # Required string
    email: str = Field(unique=True, index=True)

    # Optional string
    bio: str | None = Field(default=None)

    # String with max length (for VARCHAR)
    username: str = Field(max_length=50, unique=True)

    # Text field (unlimited length)
    content: str = Field(sa_type=Text)
```

### Numeric Fields

```python
from decimal import Decimal
from sqlalchemy import Numeric

class Product(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)

    # Integer
    quantity: int = Field(default=0)

    # Float
    rating: float = Field(default=0.0)

    # Decimal (for money)
    price: Decimal = Field(default=0, sa_type=Numeric(10, 2))
```

### Boolean Fields

```python
class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)

    # Boolean with default
    is_active: bool = Field(default=True)
    is_completed: bool = Field(default=False)
```

### DateTime Fields

```python
from datetime import datetime, date, time, timezone

class Event(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)

    # DateTime with auto-now
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

    # Optional datetime
    completed_at: datetime | None = Field(default=None)

    # Date only
    event_date: date

    # Time only
    start_time: time
```

### Enum Fields

```python
from enum import Enum

class TaskStatus(str, Enum):
    PENDING = "pending"
    IN_PROGRESS = "in_progress"
    COMPLETED = "completed"

class Task(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    status: TaskStatus = Field(default=TaskStatus.PENDING)
```

### JSON Fields

```python
from sqlalchemy import JSON

class Settings(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)

    # JSON field (dict)
    preferences: dict = Field(default_factory=dict, sa_type=JSON)

    # JSON field (list)
    tags: list[str] = Field(default_factory=list, sa_type=JSON)
```

### UUID Fields

```python
from uuid import UUID, uuid4

class Document(SQLModel, table=True):
    # UUID as primary key
    id: UUID = Field(default_factory=uuid4, primary_key=True)

    # UUID as regular field
    owner_id: UUID
```

## Primary Keys

### Auto-increment Integer (Default)

```python
class Model(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
```

### UUID Primary Key

```python
from uuid import UUID, uuid4

class Model(SQLModel, table=True):
    id: UUID = Field(default_factory=uuid4, primary_key=True)
```

### Composite Primary Key

```python
class OrderItem(SQLModel, table=True):
    order_id: int = Field(foreign_key="order.id", primary_key=True)
    product_id: int = Field(foreign_key="product.id", primary_key=True)
    quantity: int
```

## Indexes and Constraints

### Single Column Index

```python
class User(SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    email: str = Field(index=True)  # Simple index
    username: str = Field(unique=True)  # Unique constraint (includes index)
```

### Composite Index

```python
from sqlalchemy import Index

class Task(SQLModel, table=True):
    __table_args__ = (
        Index("ix_task_user_status", "user_id", "status"),
    )

    id: int | None = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id")
    status: str
```

### Check Constraint

```python
from sqlalchemy import CheckConstraint

class Product(SQLModel, table=True):
    __table_args__ = (
        CheckConstraint("price >= 0", name="check_positive_price"),
    )

    id: int | None = Field(default=None, primary_key=True)
    price: float
```

## Table Configuration

### Custom Table Name

```python
class UserAccount(SQLModel, table=True):
    __tablename__ = "users"  # Custom table name

    id: int | None = Field(default=None, primary_key=True)
```

### Schema (PostgreSQL)

```python
class AuditLog(SQLModel, table=True):
    __table_args__ = {"schema": "audit"}

    id: int | None = Field(default=None, primary_key=True)
```

## Timestamp Patterns

### Created/Updated Timestamps

```python
from datetime import datetime, timezone

class TimestampMixin(SQLModel):
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

class Task(TimestampMixin, SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str
```

### Auto-update on Change (SQLAlchemy)

```python
from datetime import datetime, timezone
from sqlalchemy import event
from sqlmodel import Session

@event.listens_for(Session, "before_flush")
def update_timestamps(session, flush_context, instances):
    for obj in session.dirty:
        if hasattr(obj, "updated_at"):
            obj.updated_at = datetime.now(timezone.utc)
```

## Soft Delete Pattern

```python
from datetime import datetime, timezone

class SoftDeleteMixin(SQLModel):
    deleted_at: datetime | None = Field(default=None, index=True)

    @property
    def is_deleted(self) -> bool:
        return self.deleted_at is not None

    def soft_delete(self):
        self.deleted_at = datetime.now(timezone.utc)

class Task(SoftDeleteMixin, SQLModel, table=True):
    id: int | None = Field(default=None, primary_key=True)
    title: str

# Query active records only
def get_active_tasks(session: Session) -> list[Task]:
    return session.exec(
        select(Task).where(Task.deleted_at == None)
    ).all()
```

## Complete Example

```python
from datetime import datetime, timezone
from decimal import Decimal
from enum import Enum
from uuid import UUID, uuid4

from sqlalchemy import JSON, Numeric, Index
from sqlmodel import Field, SQLModel

class OrderStatus(str, Enum):
    PENDING = "pending"
    PROCESSING = "processing"
    SHIPPED = "shipped"
    DELIVERED = "delivered"
    CANCELLED = "cancelled"

class Order(SQLModel, table=True):
    __table_args__ = (
        Index("ix_order_user_status", "user_id", "status"),
    )

    # Primary key
    id: UUID = Field(default_factory=uuid4, primary_key=True)

    # Foreign key
    user_id: int = Field(foreign_key="user.id", index=True)

    # Enum
    status: OrderStatus = Field(default=OrderStatus.PENDING)

    # Decimal for money
    total: Decimal = Field(default=0, sa_type=Numeric(10, 2))

    # JSON metadata
    shipping_address: dict = Field(default_factory=dict, sa_type=JSON)

    # Timestamps
    created_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )
    updated_at: datetime = Field(
        default_factory=lambda: datetime.now(timezone.utc)
    )

    # Soft delete
    deleted_at: datetime | None = Field(default=None)
```
