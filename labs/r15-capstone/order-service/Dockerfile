FROM python:3.12-slim
RUN pip install --no-cache-dir \
    psycopg2-binary==2.9.9 \
    redis==5.0.1 \
    kafka-python==3.0.11 \
    opentelemetry-sdk==1.27.0 \
    opentelemetry-exporter-otlp-proto-http==1.27.0
COPY server.py /server.py
ENTRYPOINT ["python3", "-u", "/server.py"]
