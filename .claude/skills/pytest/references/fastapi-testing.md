# FastAPI Testing Reference

## Table of Contents
- [TestClient Basics](#testclient-basics)
- [Async Testing](#async-testing)
- [Dependency Overrides](#dependency-overrides)
- [Testing Authentication](#testing-authentication)
- [Request/Response Testing](#requestresponse-testing)
- [WebSocket Testing](#websocket-testing)
- [Background Tasks Testing](#background-tasks-testing)

---

## TestClient Basics

### Setup
```python
from fastapi import FastAPI
from fastapi.testclient import TestClient

app = FastAPI()

@app.get("/")
def read_root():
    return {"message": "Hello World"}

# Direct usage
client = TestClient(app)

def test_read_root():
    response = client.get("/")
    assert response.status_code == 200
    assert response.json() == {"message": "Hello World"}
```

### Fixture-Based Setup
```python
# conftest.py
import pytest
from fastapi.testclient import TestClient
from myapp.main import app

@pytest.fixture(scope="module")
def client():
    with TestClient(app) as c:
        yield c

# test_api.py
def test_endpoint(client):
    response = client.get("/items/1")
    assert response.status_code == 200
```

### HTTP Methods
```python
def test_crud_operations(client):
    # GET
    response = client.get("/items/1")

    # POST with JSON
    response = client.post("/items/", json={"name": "Item", "price": 10.5})

    # PUT
    response = client.put("/items/1", json={"name": "Updated"})

    # PATCH
    response = client.patch("/items/1", json={"price": 15.0})

    # DELETE
    response = client.delete("/items/1")
```

### Query Parameters and Headers
```python
def test_with_params(client):
    # Query parameters
    response = client.get("/items/", params={"skip": 0, "limit": 10})

    # Headers
    response = client.get("/items/", headers={"X-Token": "secret"})

    # Cookies
    response = client.get("/items/", cookies={"session": "abc123"})
```

---

## Async Testing

### Using httpx with ASGITransport
```python
import pytest
from httpx import AsyncClient, ASGITransport
from myapp.main import app

@pytest.fixture
async def async_client():
    async with AsyncClient(
        transport=ASGITransport(app=app),
        base_url="http://test"
    ) as ac:
        yield ac

@pytest.mark.anyio
async def test_async_endpoint(async_client):
    response = await async_client.get("/")
    assert response.status_code == 200
```

### Async Fixtures
```python
@pytest.fixture
async def async_db_session():
    async with async_session_maker() as session:
        yield session
        await session.rollback()

@pytest.mark.anyio
async def test_async_db(async_client, async_db_session):
    # Test with async database session
    response = await async_client.get("/users/")
    assert response.status_code == 200
```

### Configure pytest-anyio
```python
# conftest.py
import pytest

@pytest.fixture(scope="session")
def anyio_backend():
    return "asyncio"  # or "trio"
```

---

## Dependency Overrides

### Basic Override
```python
from fastapi import Depends

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()

@app.get("/items/")
def read_items(db: Session = Depends(get_db)):
    return db.query(Item).all()

# In tests
def get_test_db():
    db = TestingSessionLocal()
    try:
        yield db
    finally:
        db.close()

@pytest.fixture
def client():
    app.dependency_overrides[get_db] = get_test_db
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

### Override with Factory
```python
@pytest.fixture
def override_dependencies():
    """Flexible dependency override fixture."""
    overrides = {}

    def _override(dependency, replacement):
        app.dependency_overrides[dependency] = replacement
        overrides[dependency] = replacement

    yield _override

    for dep in overrides:
        app.dependency_overrides.pop(dep, None)

def test_with_mock_service(client, override_dependencies):
    mock_service = Mock()
    mock_service.get_items.return_value = [{"id": 1}]
    override_dependencies(get_service, lambda: mock_service)

    response = client.get("/items/")
    assert len(response.json()) == 1
```

### Override Settings
```python
from functools import lru_cache
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    database_url: str = "postgresql://..."
    api_key: str = ""

@lru_cache
def get_settings():
    return Settings()

# In tests
@pytest.fixture
def test_settings():
    return Settings(
        database_url="sqlite:///./test.db",
        api_key="test-key"
    )

@pytest.fixture
def client(test_settings):
    app.dependency_overrides[get_settings] = lambda: test_settings
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()
```

---

## Testing Authentication

### JWT Authentication
```python
from jose import jwt

def create_test_token(user_id: int, role: str = "user"):
    return jwt.encode(
        {"sub": str(user_id), "role": role},
        "test-secret",
        algorithm="HS256"
    )

@pytest.fixture
def auth_headers():
    token = create_test_token(user_id=1)
    return {"Authorization": f"Bearer {token}"}

def test_protected_endpoint(client, auth_headers):
    response = client.get("/protected/", headers=auth_headers)
    assert response.status_code == 200

def test_unauthorized(client):
    response = client.get("/protected/")
    assert response.status_code == 401
```

### Override Current User
```python
from myapp.auth import get_current_user

@pytest.fixture
def mock_current_user():
    return {"id": 1, "email": "test@example.com", "role": "admin"}

@pytest.fixture
def authenticated_client(mock_current_user):
    app.dependency_overrides[get_current_user] = lambda: mock_current_user
    with TestClient(app) as c:
        yield c
    app.dependency_overrides.clear()

def test_admin_only(authenticated_client):
    response = authenticated_client.get("/admin/dashboard")
    assert response.status_code == 200
```

---

## Request/Response Testing

### File Uploads
```python
def test_file_upload(client):
    files = {"file": ("test.txt", b"file content", "text/plain")}
    response = client.post("/upload/", files=files)
    assert response.status_code == 200

def test_multiple_files(client):
    files = [
        ("files", ("file1.txt", b"content1", "text/plain")),
        ("files", ("file2.txt", b"content2", "text/plain")),
    ]
    response = client.post("/upload-multiple/", files=files)
    assert response.status_code == 200
```

### Form Data
```python
def test_form_submission(client):
    response = client.post(
        "/login/",
        data={"username": "user", "password": "pass"}
    )
    assert response.status_code == 200
```

### Validation Error Testing
```python
def test_validation_error(client):
    response = client.post("/items/", json={"name": ""})  # Invalid
    assert response.status_code == 422
    assert "detail" in response.json()

    errors = response.json()["detail"]
    assert any(e["loc"] == ["body", "name"] for e in errors)
```

### Response Headers and Cookies
```python
def test_response_headers(client):
    response = client.get("/")
    assert response.headers["content-type"] == "application/json"
    assert "x-request-id" in response.headers

def test_set_cookie(client):
    response = client.post("/login/", data={"username": "user", "password": "pass"})
    assert "session" in response.cookies
```

---

## WebSocket Testing

```python
def test_websocket(client):
    with client.websocket_connect("/ws") as websocket:
        websocket.send_json({"message": "hello"})
        data = websocket.receive_json()
        assert data["message"] == "hello"

def test_websocket_with_auth(client, auth_headers):
    with client.websocket_connect("/ws", headers=auth_headers) as ws:
        data = ws.receive_json()
        assert data["status"] == "connected"
```

---

## Background Tasks Testing

```python
from unittest.mock import patch

@app.post("/send-notification/")
async def send_notification(background_tasks: BackgroundTasks):
    background_tasks.add_task(send_email, "user@example.com")
    return {"status": "queued"}

def test_background_task(client):
    with patch("myapp.tasks.send_email") as mock_send:
        response = client.post("/send-notification/")
        assert response.status_code == 200
        # Background task runs synchronously in tests
        mock_send.assert_called_once_with("user@example.com")
```
