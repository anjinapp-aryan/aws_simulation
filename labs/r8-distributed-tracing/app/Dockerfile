FROM python:3.12-slim
RUN pip install --no-cache-dir \
    psycopg2-binary==2.9.9 \
    redis==5.0.8 \
    pika==1.3.2 \
    opentelemetry-api==1.27.0 \
    opentelemetry-sdk==1.27.0 \
    opentelemetry-exporter-otlp-proto-http==1.27.0
COPY server.py /server.py
EXPOSE 8000
ENTRYPOINT ["python3", "-u", "/server.py"]
