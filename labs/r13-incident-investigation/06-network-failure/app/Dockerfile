FROM python:3.12-slim
RUN apt-get update && apt-get install -y --no-install-recommends stress-ng curl && rm -rf /var/lib/apt/lists/*
COPY server.py /server.py
EXPOSE 8000
ENTRYPOINT ["python3", "-u", "/server.py"]
