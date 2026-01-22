#!/bin/bash
# FastAPI Project Initialization Script
# Usage: bash init-project.sh --name <project_name> --level <1-5> --db <postgres|sqlite|mongodb>

set -e

# Default values
PROJECT_NAME=""
LEVEL=""
DATABASE="sqlite"
PYTHON_VERSION="3.11"

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --name)
            PROJECT_NAME="$2"
            shift 2
            ;;
        --level)
            LEVEL="$2"
            shift 2
            ;;
        --db)
            DATABASE="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 --name <project_name> --level <1-5> --db <postgres|sqlite|mongodb>"
            exit 1
            ;;
    esac
done

# Validate inputs
if [ -z "$PROJECT_NAME" ]; then
    echo "Error: --name is required"
    exit 1
fi

if [ -z "$LEVEL" ] || [ "$LEVEL" -lt 1 ] || [ "$LEVEL" -gt 5 ]; then
    echo "Error: --level must be between 1 and 5"
    exit 1
fi

echo "Initializing FastAPI project: $PROJECT_NAME (Level $LEVEL)"

# Create project directory
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"

# Level 1: Hello World (Single file)
if [ "$LEVEL" -eq 1 ]; then
    echo "Creating Level 1 (Hello World) structure..."

    cat > main.py << 'EOF'
from fastapi import FastAPI

app = FastAPI(title="Hello World API")

@app.get("/")
def read_root():
    return {"message": "Hello World"}

@app.get("/items/{item_id}")
def read_item(item_id: int, q: str = None):
    return {"item_id": item_id, "q": q}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
EOF

    cat > requirements.txt << 'EOF'
fastapi
uvicorn[standard]
EOF

    cat > README.md << 'EOF'
# Hello World FastAPI

## Setup

```bash
pip install -r requirements.txt
```

## Run

```bash
python main.py
```

Or:

```bash
uvicorn main:app --reload
```

## API Docs

Open http://localhost:8000/docs
EOF

fi

# Level 2: Basic CRUD
if [ "$LEVEL" -eq 2 ]; then
    echo "Creating Level 2 (Basic CRUD) structure..."

    # Create directory structure
    mkdir -p app/{routers,models,schemas,crud}
    touch app/{__init__.py,routers/__init__.py,models/__init__.py,schemas/__init__.py,crud/__init__.py}

    # Database setup based on selection
    if [ "$DATABASE" = "sqlite" ]; then
        DATABASE_URL="sqlite:///./app.db"
        ASYNC_DATABASE_URL="sqlite+aiosqlite:///./app.db"
    elif [ "$DATABASE" = "postgres" ]; then
        DATABASE_URL="postgresql://postgres:postgres@localhost/appdb"
        ASYNC_DATABASE_URL="postgresql+asyncpg://postgres:postgres@localhost/appdb"
    fi

    # main.py
    cat > app/main.py << 'EOF'
from fastapi import FastAPI
from .routers import items
from .database import engine
from . import models

# Create tables
models.Base.metadata.create_all(bind=engine)

app = FastAPI(title="FastAPI CRUD App")

# Include routers
app.include_router(items.router)

@app.get("/")
def read_root():
    return {"message": "Welcome to FastAPI CRUD API"}

@app.get("/health")
def health_check():
    return {"status": "ok"}
EOF

    # config.py
    cat > app/config.py << EOF
from pydantic_settings import BaseSettings

class Settings(BaseSettings):
    DATABASE_URL: str = "$DATABASE_URL"
    SECRET_KEY: str = "your-secret-key-change-in-production"

    class Config:
        env_file = ".env"

settings = Settings()
EOF

    # database.py
    cat > app/database.py << 'EOF'
from sqlalchemy import create_engine
from sqlalchemy.ext.declarative import declarative_base
from sqlalchemy.orm import sessionmaker
from .config import settings

engine = create_engine(
    settings.DATABASE_URL,
    connect_args={"check_same_thread": False} if "sqlite" in settings.DATABASE_URL else {}
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()

def get_db():
    db = SessionLocal()
    try:
        yield db
    finally:
        db.close()
EOF

    # models/item.py
    cat > app/models/item.py << 'EOF'
from sqlalchemy import Column, Integer, String, Boolean
from ..database import Base

class Item(Base):
    __tablename__ = "items"

    id = Column(Integer, primary_key=True, index=True)
    title = Column(String, index=True)
    description = Column(String)
    completed = Column(Boolean, default=False)
EOF

    # models/__init__.py
    cat > app/models/__init__.py << 'EOF'
from .item import Item
from ..database import Base
EOF

    # schemas/item.py
    cat > app/schemas/item.py << 'EOF'
from pydantic import BaseModel

class ItemBase(BaseModel):
    title: str
    description: str | None = None
    completed: bool = False

class ItemCreate(ItemBase):
    pass

class ItemUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    completed: bool | None = None

class Item(ItemBase):
    id: int

    class Config:
        from_attributes = True
EOF

    # schemas/__init__.py
    cat > app/schemas/__init__.py << 'EOF'
from .item import Item, ItemCreate, ItemUpdate
EOF

    # crud/item.py
    cat > app/crud/item.py << 'EOF'
from sqlalchemy.orm import Session
from ..models.item import Item
from ..schemas.item import ItemCreate, ItemUpdate

def get_items(db: Session, skip: int = 0, limit: int = 100):
    return db.query(Item).offset(skip).limit(limit).all()

def get_item(db: Session, item_id: int):
    return db.query(Item).filter(Item.id == item_id).first()

def create_item(db: Session, item: ItemCreate):
    db_item = Item(**item.dict())
    db.add(db_item)
    db.commit()
    db.refresh(db_item)
    return db_item

def update_item(db: Session, item_id: int, item: ItemUpdate):
    db_item = db.query(Item).filter(Item.id == item_id).first()
    if db_item:
        update_data = item.dict(exclude_unset=True)
        for key, value in update_data.items():
            setattr(db_item, key, value)
        db.commit()
        db.refresh(db_item)
    return db_item

def delete_item(db: Session, item_id: int):
    db_item = db.query(Item).filter(Item.id == item_id).first()
    if db_item:
        db.delete(db_item)
        db.commit()
    return db_item
EOF

    # routers/items.py
    cat > app/routers/items.py << 'EOF'
from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from .. import schemas, crud
from ..database import get_db

router = APIRouter(prefix="/items", tags=["items"])

@router.get("/", response_model=list[schemas.Item])
def list_items(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
    items = crud.get_items(db, skip=skip, limit=limit)
    return items

@router.post("/", response_model=schemas.Item, status_code=status.HTTP_201_CREATED)
def create_item(item: schemas.ItemCreate, db: Session = Depends(get_db)):
    return crud.create_item(db, item)

@router.get("/{item_id}", response_model=schemas.Item)
def get_item(item_id: int, db: Session = Depends(get_db)):
    item = crud.get_item(db, item_id)
    if not item:
        raise HTTPException(status_code=404, detail="Item not found")
    return item

@router.put("/{item_id}", response_model=schemas.Item)
def update_item(item_id: int, item: schemas.ItemUpdate, db: Session = Depends(get_db)):
    db_item = crud.update_item(db, item_id, item)
    if not db_item:
        raise HTTPException(status_code=404, detail="Item not found")
    return db_item

@router.delete("/{item_id}", status_code=status.HTTP_204_NO_CONTENT)
def delete_item(item_id: int, db: Session = Depends(get_db)):
    db_item = crud.delete_item(db, item_id)
    if not db_item:
        raise HTTPException(status_code=404, detail="Item not found")
    return None
EOF

    # requirements.txt
    if [ "$DATABASE" = "postgres" ]; then
        cat > requirements.txt << 'EOF'
fastapi
uvicorn[standard]
sqlalchemy
psycopg2-binary
pydantic-settings
EOF
    else
        cat > requirements.txt << 'EOF'
fastapi
uvicorn[standard]
sqlalchemy
pydantic-settings
EOF
    fi

    # .env
    cat > .env << EOF
DATABASE_URL=$DATABASE_URL
SECRET_KEY=dev-secret-key-change-in-production
EOF

    # .gitignore
    cat > .gitignore << 'EOF'
__pycache__/
*.py[cod]
*$py.class
*.so
.env
*.env
*.db
.venv/
venv/
ENV/
EOF

    # README.md
    cat > README.md << 'EOF'
# FastAPI CRUD Application

## Setup

```bash
python -m venv venv
source venv/bin/activate  # On Windows: venv\Scripts\activate
pip install -r requirements.txt
```

## Run

```bash
uvicorn app.main:app --reload
```

## API Docs

- Swagger UI: http://localhost:8000/docs
- ReDoc: http://localhost:8000/redoc

## Endpoints

- `GET /items` - List all items
- `POST /items` - Create new item
- `GET /items/{id}` - Get item by ID
- `PUT /items/{id}` - Update item
- `DELETE /items/{id}` - Delete item
EOF

fi

# Level 3+: Not implemented in script (too complex)
if [ "$LEVEL" -ge 3 ]; then
    echo "Level $LEVEL projects are complex and should be created manually or via Claude Code."
    echo "Use the templates in assets/templates/ as reference."
fi

echo ""
echo "✓ Project '$PROJECT_NAME' created successfully!"
echo ""
echo "Next steps:"
echo "  cd $PROJECT_NAME"
echo "  python -m venv venv"
echo "  source venv/bin/activate"
echo "  pip install -r requirements.txt"
if [ "$LEVEL" -eq 1 ]; then
    echo "  python main.py"
else
    echo "  uvicorn app.main:app --reload"
fi
echo ""
echo "Then open http://localhost:8000/docs"
