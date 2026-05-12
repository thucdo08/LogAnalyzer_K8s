# =============================================================
# Stage 1: Builder — cài dependencies vào user local
# =============================================================
FROM python:3.10-slim AS builder

WORKDIR /build

# Chỉ copy requirements trước để tận dụng Docker layer cache
COPY requirements.txt .

# Cài vào /root/.local (user install, không global)
RUN pip install --user --no-cache-dir -r requirements.txt

# =============================================================
# Stage 2: Runtime — image nhỏ gọn, không có build artifacts
# =============================================================
FROM python:3.10-slim AS runtime

# Security: Chạy với non-root user (tránh privilege escalation)
RUN useradd -r -u 1001 -g root appuser

WORKDIR /app

# Copy chỉ các packages đã cài từ stage builder
COPY --from=builder /root/.local /home/appuser/.local

# Copy source code
COPY --chown=appuser:root . .

# Chuyển sang non-root user
USER appuser

# Đảm bảo user packages được tìm thấy trong PATH
ENV PATH=/home/appuser/.local/bin:$PATH \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

EXPOSE 8000

# Healthcheck tích hợp cho Docker (K8s dùng probe riêng)
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8000/health')" || exit 1

CMD ["python", "app.py"]