FROM python:3.12-slim-bookworm
WORKDIR /app
COPY runner/requirements.txt runner/requirements.txt
RUN pip install --no-cache-dir -r runner/requirements.txt
COPY runner runner
COPY db db
COPY workloads workloads
COPY tests tests
ENV PYTHONUNBUFFERED=1
ENTRYPOINT ["python", "-m", "runner"]
