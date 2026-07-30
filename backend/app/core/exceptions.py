"""Custom exceptions and their FastAPI handlers."""
from fastapi import Request
from fastapi.responses import JSONResponse


class QuantumTimeoutError(Exception):
    """Raised internally when the QAOA path breaches QAOA_TIMEOUT_S.

    Callers should catch this and fall back to the classical solver (FR-46)
    rather than let it propagate — it is registered here mainly so a stray
    escape still degrades gracefully instead of 500-ing.
    """


class DataUnavailableError(Exception):
    """Raised when a required data source has no usable value (e.g. district
    not found in the bundled SHC table). Distinct from adapter failures,
    which return None and downgrade data_mode instead of raising.
    """


async def quantum_timeout_handler(request: Request, exc: QuantumTimeoutError) -> JSONResponse:
    return JSONResponse(
        status_code=200,
        content={"detail": "QAOA solver timed out; classical fallback used.", "solver": "classical_fallback"},
    )


async def data_unavailable_handler(request: Request, exc: DataUnavailableError) -> JSONResponse:
    return JSONResponse(status_code=422, content={"detail": str(exc)})


def register_exception_handlers(app) -> None:
    app.add_exception_handler(QuantumTimeoutError, quantum_timeout_handler)
    app.add_exception_handler(DataUnavailableError, data_unavailable_handler)
