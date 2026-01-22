from contextlib import asynccontextmanager

from fastapi import FastAPI

from app.database import create_db_and_tables
from app.routers import todos


@asynccontextmanager
async def lifespan(app: FastAPI):
    create_db_and_tables()
    yield


app = FastAPI(title="Todo API", lifespan=lifespan)
app.include_router(todos.router)


@app.get("/")
def root():
    return {"message": "Todo API", "docs": "/docs"}
