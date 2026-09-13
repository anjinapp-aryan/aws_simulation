FROM python:3.12-slim
RUN pip install --no-cache-dir psycopg2-binary==2.9.9 kafka-python==3.0.11
COPY consumer.py /consumer.py
ENTRYPOINT ["python3", "-u", "/consumer.py"]
