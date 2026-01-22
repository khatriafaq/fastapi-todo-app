---
name: pytest
description: |
  Write and organize pytest tests for Python applications, with focus on FastAPI.
  Use when: (1) Writing new tests for endpoints or functions, (2) Setting up test
  infrastructure (conftest.py, fixtures), (3) Testing database operations with
  isolation, (4) Debugging test failures, (5) Adding async test support.
---

# Pytest Testing

## Quick Reference

| Task | Reference |
|------|-----------|
| Fixtures, parametrize, markers | [pytest-patterns.md](references/pytest-patterns.md) |
| TestClient, async, auth testing | [fastapi-testing.md](references/fastapi-testing.md) |
| DB setup, factories, isolation | [database-testing.md](references/database-testing.md) |

---

## Project Structure

```
project/
├── app/
│   ├── main.py
│   ├── models.py
│   ├── dependencies.py
│   └── routers/
├── tests/
│   ├── conftest.py          # Shared fixtures
│   ├── test_main.py
│   └── routers/
│       └── test_items.py
├── pytest.ini
└── requirements-test.txt
```

---

## Core Setup

### conftest.py (FastAPI + SQLAlchemy)
```python
import pytest
from fastapi.testclient import TestClient
from sqlalchemy import create_engine
from sqlalchemy.orm import sessionmaker

from app.main import app
from app.database import Base
from app.dependencies import get_db

SQLALCHEMY_TEST_URL = "sqlite:///./test.db"
engine = create_engine(SQLALCHEMY_TEST_URL, connect_args={"check_same_thread": False})
TestingSessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

@pytest.fixture(scope="session")
def setup_database():
    Base.metadata.create_all(bind=engine)
    yield
    Base.metadata.drop_all(bind=engine)

@pytest.fixture
def db_session(setup_database):
    connection = engine.connect()
    transaction = connection.begin()
    session = TestingSessionLocal(bind=connection)
    yield session
    session.close()
    transaction.rollback()
    connection.close()

@pytest.fixture
def client(db_session):
    def override_get_db():
        yield db_session
    app.dependency_overrides[get_db] = override_get_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

### pytest.ini
```ini
[pytest]
testpaths = tests
python_files = test_*.py
python_functions = test_*
markers =
    slow: slow running tests
    integration: integration tests
```

### requirements-test.txt
```
pytest>=7.0.0
pytest-anyio>=0.0.0
httpx>=0.24.0
factory-boy>=3.0.0
```

---

## Common Patterns

### Basic Endpoint Test
```python
def test_read_items(client):
    response = client.get("/items/")
    assert response.status_code == 200
    assert isinstance(response.json(), list)
```

### Test with Authentication
```python
@pytest.fixture
def auth_headers():
    return {"Authorization": "Bearer test-token"}

def test_protected_endpoint(client, auth_headers):
    response = client.get("/protected/", headers=auth_headers)
    assert response.status_code == 200
```

### Parametrized Validation Test
```python
@pytest.mark.parametrize("payload,expected_status", [
    ({"name": "Valid"}, 201),
    ({"name": ""}, 422),
    ({}, 422),
])
def test_create_item_validation(client, payload, expected_status):
    response = client.post("/items/", json=payload)
    assert response.status_code == expected_status
```

### Async Test
```python
import pytest
from httpx import AsyncClient, ASGITransport
from app.main import app

@pytest.mark.anyio
async def test_async_endpoint():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        response = await ac.get("/")
    assert response.status_code == 200
```

---

## Running Tests

```bash
# Run all tests
pytest

# Run with verbose output
pytest -v

# Run specific file
pytest tests/test_main.py

# Run specific test
pytest tests/test_main.py::test_read_root

# Run by marker
pytest -m "not slow"

# Run with coverage
pytest --cov=app --cov-report=html
```
