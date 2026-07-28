# ── Build stage ─────────────────────────────────────────────────────────────────
FROM python:3.12-slim AS builder

WORKDIR /build
COPY requirements.txt .

# oemer needs torch; we install CPU-only to keep the image manageable (~2 GB)
RUN pip install --no-cache-dir --upgrade pip \
 && pip install --no-cache-dir torch torchvision --index-url https://download.pytorch.org/whl/cpu \
 && pip install --no-cache-dir -r requirements.txt

# ── Runtime stage ────────────────────────────────────────────────────────────────
FROM python:3.12-slim

# System libraries needed by librosa / soundfile
RUN apt-get update && apt-get install -y --no-install-recommends \
    libsndfile1 libgomp1 ffmpeg curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Copy installed packages from builder
COPY --from=builder /usr/local/lib/python3.12/site-packages /usr/local/lib/python3.12/site-packages
COPY --from=builder /usr/local/bin /usr/local/bin

# Copy application source
COPY . .

# Create data directories
RUN mkdir -p data/scores data/musicxml data/chroma

EXPOSE 8000

CMD ["python", "run.py"]
