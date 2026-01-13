FROM python:3.13-slim

RUN apt-get update && apt-get install -y \
    build-essential \
    tesseract-ocr \
    tesseract-ocr-eng \
    poppler-utils

RUN mkdir /app
WORKDIR /app

COPY --from=ghcr.io/astral-sh/uv:latest /uv /bin/uv

COPY ai-engine/pyproject.toml ai-engine/uv.lock  ./

RUN uv venv ./venv

RUN uv sync --frozen

COPY ai-engine/ ./

COPY config/workflows.yml /app/app/workflows/workflows.yml

ENV PYTHONUNBUFFERED=1
ENV PYTHONDONTWRITEBYTECODE=1
ENV PATH=/app/.venv/bin:$PATH
ENV PYTHONPATH=/app/app

CMD ["python", "app/temporal/worker.py"]
