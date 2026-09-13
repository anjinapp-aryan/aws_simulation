FROM python:3.12-slim
RUN pip install --no-cache-dir pika==1.3.2
COPY producer.py /producer.py
ENTRYPOINT ["python3", "-u", "/producer.py"]
