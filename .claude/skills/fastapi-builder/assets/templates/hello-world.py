"""
FastAPI Hello World Example (Level 1)

A minimal FastAPI application demonstrating:
- Basic routing
- Path parameters
- Query parameters
- Auto-generated docs

Run:
    uvicorn hello-world:app --reload

Docs:
    http://localhost:8000/docs
"""

from fastapi import FastAPI

app = FastAPI(
    title="Hello World API",
    description="A simple FastAPI example",
    version="1.0.0"
)

@app.get("/")
def read_root():
    """Root endpoint"""
    return {"message": "Hello World"}

@app.get("/hello/{name}")
def greet(name: str):
    """Greet a person by name"""
    return {"message": f"Hello, {name}!"}

@app.get("/items/{item_id}")
def read_item(item_id: int, q: str = None):
    """
    Get an item by ID with optional query parameter

    - item_id: Item identifier (path parameter)
    - q: Optional query string
    """
    return {"item_id": item_id, "q": q}

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(app, host="0.0.0.0", port=8000)
