# Pytest Patterns Reference

## Table of Contents
- [Fixtures](#fixtures)
- [Parametrize](#parametrize)
- [Markers](#markers)
- [Conftest Organization](#conftest-organization)
- [Assertions](#assertions)
- [Mocking](#mocking)

---

## Fixtures

### Basic Fixture
```python
import pytest

@pytest.fixture
def sample_user():
    return {"id": 1, "name": "Test User", "email": "test@example.com"}

def test_user_name(sample_user):
    assert sample_user["name"] == "Test User"
```

### Fixture Scopes
```python
@pytest.fixture(scope="function")  # Default - runs per test
def per_test_resource(): ...

@pytest.fixture(scope="class")  # Once per test class
def per_class_resource(): ...

@pytest.fixture(scope="module")  # Once per module
def per_module_resource(): ...

@pytest.fixture(scope="session")  # Once per test session
def per_session_resource(): ...
```

### Fixture with Cleanup (yield)
```python
@pytest.fixture
def db_connection():
    conn = create_connection()
    yield conn  # Test runs here
    conn.close()  # Cleanup after test
```

### Fixture Factory Pattern
```python
@pytest.fixture
def make_user():
    created_users = []

    def _make_user(name: str, email: str = None):
        user = {"name": name, "email": email or f"{name}@test.com"}
        created_users.append(user)
        return user

    yield _make_user
    # Cleanup all created users
    for user in created_users:
        delete_user(user)

def test_multiple_users(make_user):
    user1 = make_user("Alice")
    user2 = make_user("Bob")
    assert user1["name"] != user2["name"]
```

### Autouse Fixtures
```python
@pytest.fixture(autouse=True)
def reset_state():
    """Automatically runs before each test in scope."""
    clear_cache()
    yield
    clear_cache()
```

---

## Parametrize

### Basic Parametrization
```python
@pytest.mark.parametrize("input,expected", [
    (1, 2),
    (2, 4),
    (3, 6),
])
def test_double(input, expected):
    assert input * 2 == expected
```

### Multiple Parameters
```python
@pytest.mark.parametrize("a,b,expected", [
    (1, 2, 3),
    (5, 5, 10),
    (-1, 1, 0),
])
def test_add(a, b, expected):
    assert a + b == expected
```

### IDs for Clarity
```python
@pytest.mark.parametrize("status_code,expected_error", [
    pytest.param(400, "Bad Request", id="bad_request"),
    pytest.param(401, "Unauthorized", id="unauthorized"),
    pytest.param(404, "Not Found", id="not_found"),
])
def test_error_messages(status_code, expected_error): ...
```

### Parametrize with Fixtures
```python
@pytest.fixture(params=["sqlite", "postgres", "mysql"])
def db_engine(request):
    return create_engine(request.param)

def test_query(db_engine):  # Runs 3 times, once per engine
    result = db_engine.execute("SELECT 1")
    assert result is not None
```

### Stacked Parametrize (Cartesian Product)
```python
@pytest.mark.parametrize("method", ["GET", "POST"])
@pytest.mark.parametrize("auth", [True, False])
def test_endpoint(method, auth):  # Runs 4 times (2x2)
    ...
```

---

## Markers

### Built-in Markers
```python
@pytest.mark.skip(reason="Not implemented yet")
def test_future_feature(): ...

@pytest.mark.skipif(sys.version_info < (3, 10), reason="Requires Python 3.10+")
def test_new_syntax(): ...

@pytest.mark.xfail(reason="Known bug, fix pending")
def test_known_issue(): ...
```

### Custom Markers
```python
# conftest.py
def pytest_configure(config):
    config.addinivalue_line("markers", "slow: marks tests as slow")
    config.addinivalue_line("markers", "integration: integration tests")

# test_file.py
@pytest.mark.slow
def test_complex_calculation(): ...

@pytest.mark.integration
def test_external_api(): ...
```

Run specific markers:
```bash
pytest -m slow           # Only slow tests
pytest -m "not slow"     # Skip slow tests
pytest -m "slow or integration"
```

### Async Marker (pytest-anyio)
```python
@pytest.mark.anyio
async def test_async_function():
    result = await async_operation()
    assert result is not None
```

---

## Conftest Organization

### Project Structure
```
project/
├── conftest.py              # Shared fixtures (root)
├── tests/
│   ├── conftest.py          # Test-wide fixtures
│   ├── unit/
│   │   ├── conftest.py      # Unit test fixtures
│   │   └── test_models.py
│   ├── integration/
│   │   ├── conftest.py      # Integration fixtures
│   │   └── test_api.py
│   └── e2e/
│       ├── conftest.py      # E2E fixtures
│       └── test_flows.py
```

### Conftest Best Practices
```python
# tests/conftest.py
import pytest

# Shared fixtures available to all tests
@pytest.fixture(scope="session")
def app():
    """Create application instance for testing."""
    from myapp.main import create_app
    return create_app(testing=True)

@pytest.fixture
def client(app):
    """Test client for API requests."""
    from fastapi.testclient import TestClient
    return TestClient(app)

# Register custom markers
def pytest_configure(config):
    config.addinivalue_line("markers", "slow: slow running tests")
    config.addinivalue_line("markers", "integration: integration tests")
```

---

## Assertions

### Basic Assertions
```python
def test_assertions():
    assert value == expected
    assert value != other
    assert value is None
    assert value is not None
    assert value in collection
    assert isinstance(value, ExpectedType)
```

### Exception Testing
```python
def test_raises_exception():
    with pytest.raises(ValueError) as exc_info:
        raise ValueError("Invalid input")
    assert "Invalid" in str(exc_info.value)

def test_raises_with_match():
    with pytest.raises(ValueError, match=r"Invalid.*input"):
        raise ValueError("Invalid user input")
```

### Approximate Comparisons
```python
def test_floating_point():
    assert 0.1 + 0.2 == pytest.approx(0.3)
    assert result == pytest.approx(expected, rel=1e-3)  # Relative tolerance
    assert result == pytest.approx(expected, abs=0.01)  # Absolute tolerance
```

---

## Mocking

### Basic Mock with monkeypatch
```python
def test_with_monkeypatch(monkeypatch):
    monkeypatch.setattr("mymodule.external_api", lambda: {"status": "ok"})
    result = function_using_api()
    assert result["status"] == "ok"

def test_env_variable(monkeypatch):
    monkeypatch.setenv("API_KEY", "test-key")
    assert os.getenv("API_KEY") == "test-key"
```

### unittest.mock Integration
```python
from unittest.mock import Mock, patch, AsyncMock

def test_with_mock():
    mock_service = Mock()
    mock_service.get_data.return_value = {"id": 1}

    result = process_data(mock_service)
    mock_service.get_data.assert_called_once()

@patch("mymodule.external_service")
def test_with_patch(mock_service):
    mock_service.fetch.return_value = "data"
    result = my_function()
    assert result == "data"

# Async mocking
@pytest.mark.anyio
async def test_async_mock():
    mock_client = AsyncMock()
    mock_client.fetch.return_value = {"data": "test"}
    result = await async_function(mock_client)
    assert result["data"] == "test"
```

### Mock Fixtures
```python
@pytest.fixture
def mock_redis(monkeypatch):
    cache = {}
    monkeypatch.setattr("myapp.cache.redis_client.get", lambda k: cache.get(k))
    monkeypatch.setattr("myapp.cache.redis_client.set", lambda k, v: cache.update({k: v}))
    return cache
```
