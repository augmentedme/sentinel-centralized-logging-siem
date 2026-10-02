FROM python:3.12-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

# Run as a fixed, unprivileged user. UID 10001 owns /var/log/webapp on the host.
RUN useradd --uid 10001 --no-create-home --shell /usr/sbin/nologin appuser

WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app.py .

USER 10001
EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8000/health')"

CMD ["gunicorn", "--bind", "0.0.0.0:8000", "--workers", "2", \
     "--worker-tmp-dir", "/dev/shm", "--access-logfile", "-", "app:app"]
