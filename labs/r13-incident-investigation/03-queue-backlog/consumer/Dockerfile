FROM python:3.12-slim
RUN pip install --no-cache-dir pika==1.3.2 psycopg2-binary==2.9.9
COPY consumer.py /consumer.py
ENTRYPOINT ["python3", "-u", "/consumer.py"]
