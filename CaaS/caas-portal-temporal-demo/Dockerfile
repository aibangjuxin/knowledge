FROM python:3.11-slim AS base

ENV PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PYTHONDONTWRITEBYTECODE=1

WORKDIR /app

# System deps for httpx/uuid etc are not needed; FastAPI + Temporal are pure Python.
# Keep image minimal.
RUN apt-get update -qq && apt-get install -y --no-install-recommends \
        curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

COPY pyproject.toml ./
COPY api/ ./api/
COPY workflow/ ./workflow/
COPY k8s_stub/ ./k8s_stub/

# Install Python deps (production only, no dev/test tooling).
RUN pip install --upgrade pip && pip install \
    "fastapi>=0.110" \
    "uvicorn[standard]>=0.27" \
    "pydantic>=2.6" \
    "temporalio>=1.4" \
    "httpx>=0.27" \
    "sse-starlette>=2.0" \
    "python-dotenv>=1.0"

EXPOSE 8000 8001 8010

# Default command (overridden by compose for individual services).
CMD ["uvicorn", "api.main:app", "--host", "0.0.0.0", "--port", "8000"]
