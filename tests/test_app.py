from fastapi.testclient import TestClient

from app.main import app


def test_health_route_is_registered():
    client = TestClient(app)
    response = client.get("/api/health")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_planned_routes_are_registered():
    paths = set(app.openapi().get("paths", {}))
    assert "/api/auth/signup" in paths
    assert "/api/auth/login" in paths
    assert "/api/permissions/check" in paths
    assert "/api/config" in paths
    assert "/api/meter/reserve" in paths
    assert "/api/jobs" in paths
