"""Thread-safe ring buffer + SSE fan-out for pipeline progress events."""
from __future__ import annotations

import asyncio
import threading
from collections import deque
from datetime import UTC, datetime
from typing import Any, AsyncIterator

_MAX_EVENTS = 500
_REPLAY_ON_CONNECT = 50

_lock = threading.Lock()
_buffer: deque[dict[str, Any]] = deque(maxlen=_MAX_EVENTS)
_subscribers: list[asyncio.Queue[dict[str, Any]]] = []


def emit(stage: str, message: str, *, level: str = "info", data: dict[str, Any] | None = None) -> dict[str, Any]:
    event = {
        "ts": datetime.now(UTC).isoformat(),
        "level": level,
        "stage": stage,
        "message": message,
        "data": data or {},
    }
    with _lock:
        _buffer.append(event)
        for q in list(_subscribers):
            try:
                q.put_nowait(event)
            except asyncio.QueueFull:
                pass
    return event


def recent(n: int = _REPLAY_ON_CONNECT) -> list[dict[str, Any]]:
    with _lock:
        return list(_buffer)[-n:]


async def subscribe() -> AsyncIterator[dict[str, Any]]:
    q: asyncio.Queue[dict[str, Any]] = asyncio.Queue(maxsize=200)
    with _lock:
        _subscribers.append(q)
        replay = list(_buffer)[-_REPLAY_ON_CONNECT:]
    for event in replay:
        await q.put(event)
    try:
        while True:
            yield await q.get()
    finally:
        with _lock:
            if q in _subscribers:
                _subscribers.remove(q)
