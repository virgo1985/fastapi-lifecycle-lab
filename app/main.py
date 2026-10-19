"""Lifecycle Lab API: una API deliberadamente simple para demostrar el ciclo de vida.

Lo interesante no es la API, sino cómo llega a producción: gitflow, semver,
build una vez y promoción, firma, SBOM, despliegue por entornos y rollback.
"""

from __future__ import annotations

import os
from datetime import UTC, datetime
from itertools import count
from threading import Lock

from fastapi import FastAPI, HTTPException, status
from prometheus_fastapi_instrumentator import Instrumentator
from pydantic import BaseModel, Field

from app import __build_info__
from app.greetings import GREETINGS


def _env(name: str, default: str) -> str:
    return os.environ.get(name, default)


APP_VERSION = _env("APP_VERSION", "0.0.0-local")
APP_ENV = _env("APP_ENV", "local")
STARTED_AT = datetime.now(UTC)

app = FastAPI(
    title="Lifecycle Lab API",
    version=APP_VERSION,
    description="API de ejemplo para demostrar gitflow + semver + CI/CD con contenedores.",
)
Instrumentator().instrument(app).expose(app, include_in_schema=False)


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=100, examples=["teclado"])
    quantity: int = Field(default=1, ge=0, le=10_000)


class Item(ItemIn):
    id: int


class _Store:
    """Almacén en memoria. Se pierde al reiniciar: es intencionado."""

    def __init__(self) -> None:
        self._items: dict[int, Item] = {}
        self._ids = count(1)
        self._lock = Lock()

    def list(self) -> list[Item]:
        return list(self._items.values())

    def add(self, data: ItemIn) -> Item:
        with self._lock:
            item = Item(id=next(self._ids), **data.model_dump())
            self._items[item.id] = item
            return item

    def get(self, item_id: int) -> Item | None:
        return self._items.get(item_id)

    def delete(self, item_id: int) -> bool:
        with self._lock:
            return self._items.pop(item_id, None) is not None


store = _Store()


@app.get("/", tags=["info"])
def root() -> dict[str, str]:
    return {"service": "lifecycle-lab", "version": APP_VERSION, "environment": APP_ENV}


@app.get("/health", tags=["ops"])
def health() -> dict[str, str]:
    """Liveness: el proceso responde."""
    return {"status": "ok"}


@app.get("/ready", tags=["ops"])
def ready() -> dict[str, str]:
    """Readiness: aquí se comprobarían dependencias (BD, colas...). Esta API no tiene."""
    return {"status": "ready"}


@app.get("/version", tags=["info"])
def version() -> dict[str, object]:
    """Versión desplegada y procedencia de la imagen.

    `version` la fija el despliegue (APP_VERSION). `build.built_as` es la versión con la
    que se construyó la imagen: en producción suele ser una release candidate (rc),
    porque la imagen se construye una vez en `release/*` y se promociona sin reconstruir.
    """
    return {
        "version": APP_VERSION,
        "environment": APP_ENV,
        "started_at": STARTED_AT.isoformat(),
        "build": __build_info__(),
    }


@app.get("/hello", tags=["info"])
def hello() -> dict[str, object]:
    """Último saludo publicado y cuántas vueltas de demo lleva el producto."""
    return {"message": GREETINGS[-1], "round": len(GREETINGS), "version": APP_VERSION}


@app.get("/items", tags=["items"])
def list_items() -> list[Item]:
    return store.list()


@app.post("/items", status_code=status.HTTP_201_CREATED, tags=["items"])
def create_item(data: ItemIn) -> Item:
    return store.add(data)


@app.get("/items/{item_id}", tags=["items"])
def get_item(item_id: int) -> Item:
    item = store.get(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="item not found")
    return item


@app.delete("/items/{item_id}", status_code=status.HTTP_204_NO_CONTENT, tags=["items"])
def delete_item(item_id: int) -> None:
    if not store.delete(item_id):
        raise HTTPException(status_code=404, detail="item not found")
