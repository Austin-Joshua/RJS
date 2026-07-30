FROM python:3.12-slim

WORKDIR /app

# libgomp1 is required by LightGBM's OpenMP-based booster at runtime.
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY . .

ENV PYTHONUNBUFFERED=1
EXPOSE 8000

# Railway injects PORT; default 8000 for local docker runs.
CMD ["sh", "-c", "uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8000}"]
