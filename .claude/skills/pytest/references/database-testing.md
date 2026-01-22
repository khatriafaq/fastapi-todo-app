# Database Testing Reference

## Table of Contents
- [Test Database Setup](#test-database-setup)
- [Transaction Rollback Pattern](#transaction-rollback-pattern)
- [Factory Pattern](#factory-pattern)
- [Async Database Testing](#async-database-testing)
- [Test Isolation Strategies](#test-isolation-strategies)

---

## Test Database Setup

### SQLAlchemy Sync Setup
```python
# conftest.py
import pytest
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker
from myapp.database import Base
from myapp.main import app
from myapp.dependencies import get_db

SQLALCHEMY_TEST_URL = "sqlite:///./test.db"
# Or use in-memory: "sqlite:///:memory:"

engine = create_engine(
    SQLALCHEMY_TEST_URL,
    connect_args={"check_same_thread": False}  # SQLite only
)
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture(scope="session")
def setup_database():
    """Create all tables once for the test session."""
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)

@pytest.fixture
def db_session(setup_database):
    """Provide a transactional database session for each test."""
    connection = engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)

    yield session

    session.close()
    transaction.rollback()
    connection.close()

@pytest.fixture
def client(db_session):
    """Test client with database override."""
    def override_get_db():
        yield db_session

    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

### PostgreSQL with pytest-postgresql
```python
# conftest.py
import pytest
from pytest_postgresql import factories
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

postgresql_my_proc = factories.postgresql_proc(port=None)
postgresql_my = factories.postgresql("postgresql_my_proc")

@pytest.fixture
def db_session(postgresql_my):
    """Create session with real PostgreSQL."""
    connection_string = (
        f"postgresql://{postgresql_my.info.user}:"
        f"@{postgresql_my.info.host}:{postgresql_my.info.port}/"
        f"{postgresql_my.info.dbname}"
    )
    engine = create_engine(connection_string)
    Base.metadata.create_all(engine)
    Session = sessionmaker(bind=engine)
    session = Session()
    yield session
    session.close()
```

---

## Transaction Rollback Pattern

### Nested Transaction (Savepoint)
```python
@pytest.fixture
def db_session(setup_database):
    """Use savepoints for test isolation."""
    connection = engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)

    # Begin nested transaction (savepoint)
    nested = connection.begin_nested()

    @event.listens_for(session, "after_transaction_end")
    def restart_savepoint(session, transaction):
        if transaction.nested and not transaction._parent.nested:
            connection.begin_nested()

    yield session

    session.close()
    transaction.rollback()
    connection.close()
```

### Clean Slate Per Test
```python
@pytest.fixture
def clean_db(db_session):
    """Ensure clean database for each test."""
    # Clear all tables before test
    for table in reversed(Base.metadata.sorted_tables):
        db_session.execute(table.delete())
    db_session.commit()
    yield db_session
```

---

## Factory Pattern

### Simple Factory
```python
# tests/factories.py
from myapp.models import User, Item

def create_user(db, **kwargs):
    defaults = {
        "email": "test@example.com",
        "hashed_password": "hashedpassword",
        "is_active": True,
    }
    defaults.update(kwargs)
    user = User(**defaults)
    db.add(user)
    db.commit()
    db.refresh(user)
    return user

def create_item(db, owner_id: int, **kwargs):
    defaults = {
        "title": "Test Item",
        "description": "A test item",
        "owner_id": owner_id,
    }
    defaults.update(kwargs)
    item = Item(**defaults)
    db.add(item)
    db.commit()
    db.refresh(item)
    return item

# In tests
def test_user_items(db_session):
    user = create_user(db_session, email="user@test.com")
    item = create_item(db_session, owner_id=user.id, title="My Item")
    assert item.owner_id == user.id
```

### Factory Fixture Pattern
```python
@pytest.fixture
def user_factory(db_session):
    """Factory fixture for creating users."""
    created = []

    def _create(**kwargs):
        user = create_user(db_session, **kwargs)
        created.append(user)
        return user

    yield _create

    # Cleanup (optional if using transaction rollback)
    for user in created:
        db_session.delete(user)
    db_session.commit()

def test_multiple_users(user_factory):
    admin = user_factory(email="admin@test.com", is_admin=True)
    regular = user_factory(email="user@test.com")
    assert admin.is_admin
    assert not regular.is_admin
```

### Factory Boy Integration
```python
# tests/factories.py
import factory
from myapp.models import User, Item
from myapp.database import SessionLocal

class UserFactory(factory.alchemy.SQLAlchemyModelFactory):
    class Meta:
        model = User
        sqlalchemy_session = None  # Set in fixture
        sqlalchemy_session_persistence = "commit"

    email = factory.Sequence(lambda n: f"user{n}@example.com")
    hashed_password = "hashedpassword"
    is_active = True

class ItemFactory(factory.alchemy.SQLAlchemyModelFactory):
    class Meta:
        model = Item
        sqlalchemy_session = None
        sqlalchemy_session_persistence = "commit"

    title = factory.Faker("sentence", nb_words=3)
    description = factory.Faker("paragraph")
    owner = factory.SubFactory(UserFactory)

# conftest.py
@pytest.fixture
def factories(db_session):
    """Configure factories with test session."""
    UserFactory._meta.sqlalchemy_session = db_session
    ItemFactory._meta.sqlalchemy_session = db_session
    return {"user": UserFactory, "item": ItemFactory}

# In tests
def test_with_factory_boy(factories):
    user = factories["user"](email="custom@test.com")
    items = factories["item"].create_batch(3, owner=user)
    assert len(items) == 3
```

---

## Async Database Testing

### SQLAlchemy Async Setup
```python
# conftest.py
import pytest
from sqlalchemy.ext.asyncio import create_async_engine, AsyncSession
from sqlalchemy.orm import sessionmaker
from myapp.database import Base

ASYNC_TEST_URL = "sqlite+aiosqlite:///:memory:"

async_engine = create_async_engine(ASYNC_TEST_URL, echo=False)
async_session_maker = sessionmaker(
    async_engine, class_=AsyncSession, expire_on_commit=False
)

@pytest.fixture(scope="session")
async def setup_async_database():
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.create_all)
    yield
    async with async_engine.begin() as conn:
        await conn.run_sync(Base.metadata.drop_all)

@pytest.fixture
async def async_db_session(setup_async_database):
    async with async_session_maker() as session:
        yield session
        await session.rollback()

@pytest.fixture
async def async_client(async_db_session):
    async def override_get_db():
        yield async_db_session

    app.dependency_overrides[get_db] = override_get_db
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as ac:
        yield ac
    app.dependency_overrides.clear()
```

### Async Test Example
```python
@pytest.mark.anyio
async def test_create_user(async_client, async_db_session):
    response = await async_client.post(
        "/users/",
        json={"email": "test@example.com", "password": "secret"}
    )
    assert response.status_code == 201

    # Verify in database
    result = await async_db_session.execute(
        select(User).where(User.email == "test@example.com")
    )
    user = result.scalar_one()
    assert user.email == "test@example.com"
```

---

## Test Isolation Strategies

### Strategy 1: Transaction Rollback (Recommended)
```python
# Each test runs in a transaction that gets rolled back
# Pros: Fast, clean, no residual data
# Cons: Some features don't work (e.g., testing commits)

@pytest.fixture
def db_session():
    connection = engine.connect()
    transaction = connection.begin()
    session = Session(bind=connection)
    yield session
    session.close()
    transaction.rollback()
    connection.close()
```

### Strategy 2: Truncate Tables
```python
# Clear all tables between tests
# Pros: Tests real commit behavior
# Cons: Slower than rollback

@pytest.fixture
def db_session():
    session = SessionLocal()
    yield session
    session.close()
    # Truncate all tables
    for table in reversed(Base.metadata.sorted_tables):
        session.execute(table.delete())
    session.commit()
```

### Strategy 3: Separate Test Database
```python
# Use completely isolated database per test run
# Pros: Full isolation, parallel test safety
# Cons: Slowest, requires more setup

@pytest.fixture(scope="session")
def test_database():
    test_db_name = f"test_{uuid.uuid4().hex[:8]}"
    # Create database
    create_database(test_db_name)
    yield test_db_name
    # Drop database
    drop_database(test_db_name)
```

### pytest.ini Configuration
```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
asyncio_mode = auto
filterwarnings =
    ignore::DeprecationWarning
markers =
    slow: marks tests as slow
    integration: integration tests requiring database
```
