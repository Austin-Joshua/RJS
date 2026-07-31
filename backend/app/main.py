"""FastAPI application instance, CORS, and startup wiring (TRD §2)."""
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles

from app.api.v1.router import router as v1_router
from app.core.exceptions import register_exception_handlers
from app.db.session import init_db

BACKEND_ROOT = Path(__file__).resolve().parents[1]
OPS_STATIC = BACKEND_ROOT / "static" / "ops"


@asynccontextmanager
async def lifespan(app: FastAPI):
    init_db()
    yield


app = FastAPI(title="FarmSync Quantum 2.0 API", version="1.0.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

register_exception_handlers(app)
app.include_router(v1_router, prefix="/api/v1")

if OPS_STATIC.is_dir():
    app.mount("/ops", StaticFiles(directory=OPS_STATIC, html=True), name="ops")
