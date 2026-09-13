FROM python:3.12-slim
RUN pip install --no-cache-dir \
    pika==1.3.2 \
    opentelemetry-api==1.27.0 \
    opentelemetry-sdk==1.27.0 \
    opentelemetry-exporter-otlp-proto-http==1.27.0
COPY consumer.py /consumer.py
ENTRYPOINT ["python3", "-u", "/consumer.py"]
