from fastapi.testclient import TestClient

from app.main import app

client = TestClient(app)


def test_health() -> None:
    r = client.get("/health")
    assert r.status_code == 200
    assert r.json() == {"status": "ok"}


def test_ready() -> None:
    assert client.get("/ready").json()["status"] == "ready"


def test_root_reports_version_and_env() -> None:
    body = client.get("/").json()
    assert body["service"] == "lifecycle-lab"
    assert {"version", "environment"} <= body.keys()


def test_version_includes_build_info() -> None:
    body = client.get("/version").json()
    assert {"built_as", "git_sha", "git_ref", "build_date"} <= body["build"].keys()


def test_items_crud() -> None:
    created = client.post("/items", json={"name": "teclado", "quantity": 2})
    assert created.status_code == 201
    item = created.json()
    assert item["name"] == "teclado"

    assert client.get(f"/items/{item['id']}").json() == item
    assert item in client.get("/items").json()

    assert client.delete(f"/items/{item['id']}").status_code == 204
    assert client.get(f"/items/{item['id']}").status_code == 404


def test_delete_missing_item_returns_404() -> None:
    assert client.delete("/items/999999").status_code == 404


def test_validation_rejects_empty_name() -> None:
    assert client.post("/items", json={"name": ""}).status_code == 422


def test_metrics_exposed() -> None:
    client.get("/health")
    r = client.get("/metrics")
    assert r.status_code == 200
    assert "http_requests_total" in r.text
