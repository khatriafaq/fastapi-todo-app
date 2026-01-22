from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from sqlmodel import select

from app.database import SessionDep
from app.models import Todo, TodoCreate, TodoRead, TodoUpdate

router = APIRouter(prefix="/todos", tags=["todos"])


@router.get("/", response_model=list[TodoRead])
def list_todos(session: SessionDep):
    """List all todos."""
    todos = session.exec(select(Todo)).all()
    return todos


@router.get("/{todo_id}", response_model=TodoRead)
def get_todo(todo_id: int, session: SessionDep):
    """Get a single todo by ID."""
    todo = session.get(Todo, todo_id)
    if not todo:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo


@router.post("/", response_model=TodoRead, status_code=201)
def create_todo(todo_create: TodoCreate, session: SessionDep):
    """Create a new todo."""
    todo = Todo.model_validate(todo_create)
    session.add(todo)
    session.commit()
    session.refresh(todo)
    return todo


@router.patch("/{todo_id}", response_model=TodoRead)
def update_todo_patch(todo_id: int, todo_update: TodoUpdate, session: SessionDep):
    """Partially update a todo (only provided fields)."""
    todo = session.get(Todo, todo_id)
    if not todo:
        raise HTTPException(status_code=404, detail="Todo not found")

    update_data = todo_update.model_dump(exclude_unset=True)
    if update_data:
        for key, value in update_data.items():
            setattr(todo, key, value)
        todo.updated_at = datetime.now(timezone.utc)

    session.add(todo)
    session.commit()
    session.refresh(todo)
    return todo


@router.put("/{todo_id}", response_model=TodoRead)
def update_todo_put(todo_id: int, todo_update: TodoUpdate, session: SessionDep):
    """Full update a todo (all fields replaced)."""
    todo = session.get(Todo, todo_id)
    if not todo:
        raise HTTPException(status_code=404, detail="Todo not found")

    update_data = todo_update.model_dump()
    for key, value in update_data.items():
        if value is not None:
            setattr(todo, key, value)
    todo.updated_at = datetime.now(timezone.utc)

    session.add(todo)
    session.commit()
    session.refresh(todo)
    return todo


@router.delete("/{todo_id}", status_code=204)
def delete_todo(todo_id: int, session: SessionDep):
    """Delete a todo."""
    todo = session.get(Todo, todo_id)
    if not todo:
        raise HTTPException(status_code=404, detail="Todo not found")
    session.delete(todo)
    session.commit()
    return None
