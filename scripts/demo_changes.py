#!/usr/bin/env python3
"""Catálogo de cambios de la demo: código + tests listos para enseñar en el IDE.

Cada vuelta aplica el primer cambio del catálogo que aún no está en el código.
Lo usa scripts/demo.sh; también se puede llamar a mano:

    scripts/demo_changes.py plan feature|hotfix [ref]   -> "slug<TAB>título" del siguiente cambio
    scripts/demo_changes.py apply <slug>                -> escribe el cambio en el árbol de trabajo

`ref` (p. ej. origin/develop) indica de qué rama leer el código para decidir; por
defecto, el árbol de trabajo. Cuando se agotan las features, cada vuelta añade un
saludo nuevo a /hello. Cuando se agotan los hotfixes, toca resetear la demo.
"""

from __future__ import annotations

import datetime
import pathlib
import re
import subprocess
import sys
from collections.abc import Callable
from dataclasses import dataclass

ROOT = pathlib.Path(__file__).resolve().parent.parent
MAIN = ROOT / "app" / "main.py"
GREETINGS = ROOT / "app" / "greetings.py"
ITEMS_ANCHOR = '@app.get("/items", tags=["items"])'


# --------------------------------------------------------------------- utilidades
def read(path: pathlib.Path, ref: str | None) -> str:
    if ref is None:
        return path.read_text()
    rel = path.relative_to(ROOT).as_posix()
    return subprocess.run(
        ["git", "show", f"{ref}:{rel}"], cwd=ROOT, check=True, capture_output=True, text=True
    ).stdout


def ensure_import(src: str, module: str, name: str) -> str:
    """Añade `name` a la línea `from module import ...` (o crea la línea)."""
    pattern = re.compile(rf"^from {re.escape(module)} import (.+)$", re.M)
    m = pattern.search(src)
    if m is None:
        anchor = "from app import __build_info__"
        return src.replace(anchor, f"from {module} import {name}\n\n{anchor}", 1)
    names = [n.strip() for n in m.group(1).split(",")]
    if name in names:
        return src
    names = sorted({*names, name}, key=lambda n: (not n[0].isupper(), n))
    return src[: m.start()] + f"from {module} import {', '.join(names)}" + src[m.end() :]


def insert_before_items(src: str, block: str) -> str:
    """Las rutas nuevas van antes de /items/{item_id} para que FastAPI las encuentre."""
    if ITEMS_ANCHOR not in src:
        sys.exit(f"no encuentro {ITEMS_ANCHOR!r} en app/main.py")
    return src.replace(ITEMS_ANCHOR, block.strip("\n") + "\n\n\n" + ITEMS_ANCHOR, 1)


def write_test(name: str, body: str, imports: str = "") -> None:
    header = (
        "from fastapi.testclient import TestClient\n\n"
        + (imports + "\n" if imports else "")
        + "from app.main import app\n\n"
        "client = TestClient(app)\n\n\n"
    )
    (ROOT / "tests" / name).write_text(header + body.strip("\n") + "\n")


@dataclass(frozen=True)
class Change:
    slug: str
    kind: str  # feature | hotfix
    title: str
    applied: Callable[[str], bool]  # recibe app/main.py
    apply: Callable[[], None]


# --------------------------------------------------------------------- features
def _items_search() -> None:
    src = ensure_import(MAIN.read_text(), "fastapi", "Query")
    src = insert_before_items(
        src,
        '''
@app.get("/items/search", tags=["items"])
def search_items(q: str = Query(min_length=1, max_length=100)) -> list[Item]:
    """Busca items cuyo nombre contiene `q`, sin distinguir mayúsculas."""
    needle = q.casefold()
    return [item for item in store.list() if needle in item.name.casefold()]
''',
    )
    MAIN.write_text(src)
    write_test(
        "test_items_search.py",
        """
def test_search_matches_partial_name_ignoring_case() -> None:
    client.post("/items", json={"name": "Teclado mecánico"})
    client.post("/items", json={"name": "Ratón inalámbrico"})

    names = [i["name"] for i in client.get("/items/search", params={"q": "TECLADO"}).json()]

    assert "Teclado mecánico" in names
    assert "Ratón inalámbrico" not in names


def test_search_requires_a_query() -> None:
    assert client.get("/items/search").status_code == 422
""",
    )


def _items_stats() -> None:
    src = insert_before_items(
        MAIN.read_text(),
        '''
class ItemStats(BaseModel):
    count: int
    total_quantity: int


@app.get("/items/stats", tags=["items"])
def items_stats() -> ItemStats:
    """Resumen del inventario: número de items y unidades totales."""
    items = store.list()
    return ItemStats(count=len(items), total_quantity=sum(i.quantity for i in items))
''',
    )
    MAIN.write_text(src)
    write_test(
        "test_items_stats.py",
        """
def test_stats_reflect_new_items() -> None:
    before = client.get("/items/stats").json()

    client.post("/items", json={"name": "monitor", "quantity": 5})

    after = client.get("/items/stats").json()
    assert after["count"] == before["count"] + 1
    assert after["total_quantity"] == before["total_quantity"] + 5
""",
    )


def _hello_name() -> None:
    src = ensure_import(MAIN.read_text(), "fastapi", "Path")
    src = insert_before_items(
        src,
        '''
@app.get("/hello/{name}", tags=["info"])
def hello_name(name: str = Path(min_length=1, max_length=50)) -> dict[str, str]:
    """Saludo personalizado."""
    return {"message": f"{GREETINGS[-1]}, {name}!"}
''',
    )
    MAIN.write_text(src)
    write_test(
        "test_hello_name.py",
        """
def test_hello_greets_by_name() -> None:
    body = client.get("/hello/Ana").json()
    assert body["message"] == f"{GREETINGS[-1]}, Ana!"


def test_hello_rejects_very_long_names() -> None:
    assert client.get("/hello/" + "x" * 51).status_code == 422
""",
        imports="from app.greetings import GREETINGS",
    )


def _uptime() -> None:
    src = insert_before_items(
        MAIN.read_text(),
        '''
@app.get("/uptime", tags=["ops"])
def uptime() -> dict[str, float]:
    """Segundos desde que arrancó el proceso: se reinicia con cada despliegue."""
    return {"seconds": (datetime.now(UTC) - STARTED_AT).total_seconds()}
''',
    )
    MAIN.write_text(src)
    write_test(
        "test_uptime.py",
        """
def test_uptime_is_non_negative() -> None:
    assert client.get("/uptime").json()["seconds"] >= 0
""",
    )


# --------------------------------------------------------------------- hotfixes
def _trim_item_name() -> None:
    src = ensure_import(MAIN.read_text(), "pydantic", "ConfigDict")
    src = src.replace(
        "class ItemIn(BaseModel):\n",
        "class ItemIn(BaseModel):\n    model_config = ConfigDict(str_strip_whitespace=True)\n\n",
        1,
    )
    MAIN.write_text(src)
    write_test(
        "test_item_name_whitespace.py",
        """
def test_blank_names_are_rejected() -> None:
    assert client.post("/items", json={"name": "   "}).status_code == 422


def test_names_are_trimmed() -> None:
    assert client.post("/items", json={"name": "  teclado  "}).json()["name"] == "teclado"
""",
    )


def _positive_item_ids() -> None:
    src = ensure_import(MAIN.read_text(), "fastapi", "Path")
    for fn in ("get_item", "delete_item"):
        src = src.replace(f"def {fn}(item_id: int)", f"def {fn}(item_id: int = Path(ge=1))", 1)
    MAIN.write_text(src)
    write_test(
        "test_item_ids.py",
        """
def test_non_positive_ids_are_rejected() -> None:
    assert client.get("/items/0").status_code == 422
    assert client.delete("/items/-1").status_code == 422
""",
    )


CATALOG: list[Change] = [
    Change("items-search", "feature", "feat(items): búsqueda por nombre",
           lambda s: '"/items/search"' in s, _items_search),
    Change("items-stats", "feature", "feat(items): estadísticas del inventario",
           lambda s: '"/items/stats"' in s, _items_stats),
    Change("hello-name", "feature", "feat(hello): saludo personalizado",
           lambda s: '"/hello/{name}"' in s, _hello_name),
    Change("uptime", "feature", "feat(ops): endpoint de uptime",
           lambda s: '"/uptime"' in s, _uptime),
    Change("trim-item-name", "hotfix", "fix(items): rechazar nombres en blanco",
           lambda s: "str_strip_whitespace=True" in s, _trim_item_name),
    Change("positive-item-ids", "hotfix", "fix(items): rechazar ids no positivos",
           lambda s: "item_id: int = Path(ge=1)" in s, _positive_item_ids),
]  # fmt: skip


def _greeting_round(ref: str | None) -> tuple[str, str]:
    n = read(GREETINGS, ref).count('\n    "') + 1
    return f"demo-round-{n}", f"feat(hello): saludo de la vuelta {n} de la demo"


def _apply_greeting() -> None:
    src = GREETINGS.read_text()
    n = src.count('\n    "') + 1
    line = f'    "Vuelta {n} de la demo ({datetime.date.today().isoformat()})",\n'
    GREETINGS.write_text(src.replace("]\n", line + "]\n", 1))


# --------------------------------------------------------------------- CLI
def plan(kind: str, ref: str | None) -> tuple[str, str]:
    src = read(MAIN, ref)
    for c in CATALOG:
        if c.kind == kind and not c.applied(src):
            return c.slug, c.title
    if kind == "feature":
        return _greeting_round(ref)
    sys.exit("catálogo de hotfixes agotado: resetea la demo (scripts/demo.sh reset)")


def apply(slug: str) -> None:
    if slug.startswith("demo-round-"):
        _apply_greeting()
        return
    for c in CATALOG:
        if c.slug == slug:
            if c.applied(MAIN.read_text()):
                sys.exit(f"'{slug}' ya está aplicado en el árbol de trabajo")
            c.apply()
            return
    sys.exit(f"cambio desconocido: {slug}")


def main(argv: list[str]) -> None:
    # Sin `match`: el python3 del sistema en macOS es 3.9.
    if len(argv) in (2, 3) and argv[0] == "plan" and argv[1] in ("feature", "hotfix"):
        slug, title = plan(argv[1], argv[2] if len(argv) == 3 else None)
        print(f"{slug}\t{title}")
    elif len(argv) == 2 and argv[0] == "apply":
        apply(argv[1])
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main(sys.argv[1:])
