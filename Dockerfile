# syntax=docker/dockerfile:1
# Imágenes base fijadas por digest: el mismo commit construye siempre lo mismo.
# Dependabot propone las actualizaciones como PR contra develop.
ARG PYTHON_IMAGE=python:3.13.16-slim-trixie@sha256:70729b46c69b4f1e97c4822c1af3df53a1476cf5ddc6c087c0c10bc3a5678c2f

FROM ghcr.io/astral-sh/uv:0.13.6@sha256:af22a52f5eafef3d78e551599d405c02df61919d18028f0cea8eda93bc9986d0 AS uv

# ---------- build: resuelve dependencias desde uv.lock ----------
FROM ${PYTHON_IMAGE} AS builder
COPY --from=uv /uv /usr/local/bin/uv
ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=never \
    UV_PROJECT_ENVIRONMENT=/opt/venv
WORKDIR /src
COPY pyproject.toml uv.lock ./
RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --locked --no-dev --no-install-project

# ---------- runtime: sin uv, sin compiladores, usuario no root ----------
FROM ${PYTHON_IMAGE} AS runtime

ARG BUILD_VERSION=0.0.0-local
ARG BUILD_GIT_SHA=unknown
ARG BUILD_GIT_REF=unknown
ARG BUILD_DATE=unknown

LABEL org.opencontainers.image.title="lifecycle-lab" \
      org.opencontainers.image.description="API tonta para demostrar gitflow + semver + CI/CD" \
      org.opencontainers.image.source="https://github.com/virgo1985/fastapi-lifecycle-lab" \
      org.opencontainers.image.licenses="MIT" \
      org.opencontainers.image.version="${BUILD_VERSION}" \
      org.opencontainers.image.revision="${BUILD_GIT_SHA}" \
      org.opencontainers.image.created="${BUILD_DATE}"

RUN groupadd --system --gid 10001 app \
 && useradd --system --uid 10001 --gid app --no-create-home --shell /usr/sbin/nologin app

COPY --from=builder /opt/venv /opt/venv
COPY app /srv/app

ENV PATH="/opt/venv/bin:${PATH}" \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    BUILD_VERSION=${BUILD_VERSION} \
    BUILD_GIT_SHA=${BUILD_GIT_SHA} \
    BUILD_GIT_REF=${BUILD_GIT_REF} \
    BUILD_DATE=${BUILD_DATE} \
    APP_VERSION=${BUILD_VERSION}

WORKDIR /srv
USER 10001:10001
EXPOSE 8000

HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
  CMD ["python", "-c", "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health', timeout=2)"]

CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000", "--proxy-headers", "--forwarded-allow-ips", "*"]
