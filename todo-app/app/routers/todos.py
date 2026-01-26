from datetime import datetime, timezone

from fastapi import APIRouter, HTTPException
from sqlmodel import select

from app.database import SessionDep
from app.dependencies import CurrentUserDep
from app.models import Todo, TodoCreate, TodoRead, TodoUpdate

router = APIRouter(prefix="/todos", tags=["todos"])


@router.get("/", response_model=list[TodoRead])
def list_todos(session: SessionDep, current_user: CurrentUserDep):
    """List all todos for the current user."""
    todos = session.exec(
        select(Todo).where(Todo.owner_id == current_user.id)
    ).all()
    return todos


@router.get("/{todo_id}", response_model=TodoRead)
def get_todo(todo_id: int, session: SessionDep, current_user: CurrentUserDep):
    """Get a single todo by ID."""
    todo = session.exec(
        select(Todo).where(Todo.id == todo_id, Todo.owner_id == current_user.id)
    ).first()
    if not todo:
        raise HTTPException(status_code=404, detail="Todo not found")
    return todo


@router.post("/", response_model=TodoRead, status_code=201)
def create_todo(todo_create: TodoCreate, session: SessionDep, current_user: CurrentUserDep):
    """Create a new todo for the current user."""
    todo = Todo(**todo_create.model_dump(), owner_id=current_user.id)
    session.add(todo)
    session.commit()
    session.refresh(todo)
    return todo


@router.patch("/{todo_id}", response_model=TodoRead)
def update_todo_patch(todo_id: int, todo_update: TodoUpdate, session: SessionDep, current_user: CurrentUserDep):
    """Partially update a todo (only provided fields)."""
    todo = session.exec(
        select(Todo).where(Todo.id == todo_id, Todo.owner_id == current_user.id)
    ).first()
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
def update_todo_put(todo_id: int, todo_update: TodoUpdate, session: SessionDep, current_user: CurrentUserDep):
    """Full update a todo (all fields replaced)."""
    todo = session.exec(
        select(Todo).where(Todo.id == todo_id, Todo.owner_id == current_user.id)
    ).first()
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
def delete_todo(todo_id: int, session: SessionDep, current_user: CurrentUserDep):
    """Delete a todo."""
    todo = session.exec(
        select(Todo).where(Todo.id == todo_id, Todo.owner_id == current_user.id)
    ).first()
    if not todo:
        raise HTTPException(status_code=404, detail="Todo not found")
    session.delete(todo)
    session.commit()
    return None
