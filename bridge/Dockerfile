FROM python:3.13.13-slim-trixie@sha256:aa938a849bcb82dce8f49480f056ab82bf5c1c3ebc294f0430f37b6820e7f286

ENV PYTHONDONTWRITEBYTECODE=1 PYTHONUNBUFFERED=1 PYTHONPATH=/app

COPY requirements.lock /tmp/requirements.lock
RUN pip install --no-cache-dir --require-hashes -r /tmp/requirements.lock \
    && rm /tmp/requirements.lock \
    && useradd --system --uid 10001 --no-create-home bridge \
    && install -d -o bridge -m 0700 /data

COPY jukebox_bridge /app/jukebox_bridge

USER 10001
# Same contract as the systemd unit: secrets in CREDENTIALS_DIRECTORY, state in STATE_DIRECTORY.
ENV CREDENTIALS_DIRECTORY=/run/secrets STATE_DIRECTORY=/data
VOLUME /data
ENTRYPOINT ["python", "-m", "jukebox_bridge"]
