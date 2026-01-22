from fastapi.testclient import TestClient


def test_create_todo(client: TestClient):
    """Test creating a new todo."""
    response = client.post(
        "/todos/",
        json={"title": "Test Todo", "description": "Test description"},
    )
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Test Todo"
    assert data["description"] == "Test description"
    assert data["completed"] is False
    assert "id" in data
    assert "created_at" in data
    assert "updated_at" in data


def test_create_todo_minimal(client: TestClient):
    """Test creating a todo with only required fields."""
    response = client.post("/todos/", json={"title": "Minimal Todo"})
    assert response.status_code == 201
    data = response.json()
    assert data["title"] == "Minimal Todo"
    assert data["description"] is None
    assert data["completed"] is False


def test_list_todos(client: TestClient):
    """Test listing all todos."""
    # Create some todos first
    client.post("/todos/", json={"title": "Todo 1"})
    client.post("/todos/", json={"title": "Todo 2"})

    response = client.get("/todos/")
    assert response.status_code == 200
    data = response.json()
    assert len(data) == 2
    assert data[0]["title"] == "Todo 1"
    assert data[1]["title"] == "Todo 2"


def test_list_todos_empty(client: TestClient):
    """Test listing todos when none exist."""
    response = client.get("/todos/")
    assert response.status_code == 200
    assert response.json() == []


def test_get_todo(client: TestClient):
    """Test getting a single todo by ID."""
    # Create a todo first
    create_response = client.post(
        "/todos/", json={"title": "Get Me", "description": "Find this todo"}
    )
    todo_id = create_response.json()["id"]

    response = client.get(f"/todos/{todo_id}")
    assert response.status_code == 200
    data = response.json()
    assert data["id"] == todo_id
    assert data["title"] == "Get Me"
    assert data["description"] == "Find this todo"


def test_get_nonexistent_todo(client: TestClient):
    """Test getting a todo that doesn't exist."""
    response = client.get("/todos/9999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Todo not found"


def test_update_todo_patch(client: TestClient):
    """Test partial update of a todo using PATCH."""
    # Create a todo first
    create_response = client.post(
        "/todos/", json={"title": "Original Title", "description": "Original desc"}
    )
    todo_id = create_response.json()["id"]

    # Partial update - only title
    response = client.patch(f"/todos/{todo_id}", json={"title": "Updated Title"})
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Updated Title"
    assert data["description"] == "Original desc"  # Unchanged


def test_update_todo_patch_completed(client: TestClient):
    """Test marking a todo as completed using PATCH."""
    create_response = client.post("/todos/", json={"title": "Complete Me"})
    todo_id = create_response.json()["id"]

    response = client.patch(f"/todos/{todo_id}", json={"completed": True})
    assert response.status_code == 200
    assert response.json()["completed"] is True


def test_update_todo_put(client: TestClient):
    """Test full update of a todo using PUT."""
    # Create a todo first
    create_response = client.post(
        "/todos/", json={"title": "Original", "description": "Original desc"}
    )
    todo_id = create_response.json()["id"]

    # Full update
    response = client.put(
        f"/todos/{todo_id}",
        json={"title": "New Title", "description": "New desc", "completed": True},
    )
    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "New Title"
    assert data["description"] == "New desc"
    assert data["completed"] is True


def test_update_nonexistent_todo(client: TestClient):
    """Test updating a todo that doesn't exist."""
    response = client.patch("/todos/9999", json={"title": "Won't Work"})
    assert response.status_code == 404
    assert response.json()["detail"] == "Todo not found"


def test_delete_todo(client: TestClient):
    """Test deleting a todo."""
    # Create a todo first
    create_response = client.post("/todos/", json={"title": "Delete Me"})
    todo_id = create_response.json()["id"]

    # Delete it
    response = client.delete(f"/todos/{todo_id}")
    assert response.status_code == 204

    # Verify it's gone
    get_response = client.get(f"/todos/{todo_id}")
    assert get_response.status_code == 404


def test_delete_nonexistent_todo(client: TestClient):
    """Test deleting a todo that doesn't exist."""
    response = client.delete("/todos/9999")
    assert response.status_code == 404
    assert response.json()["detail"] == "Todo not found"
