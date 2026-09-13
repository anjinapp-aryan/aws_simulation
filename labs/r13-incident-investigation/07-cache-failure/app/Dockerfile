FROM python:3.12-slim
RUN pip install --no-cache-dir psycopg2-binary==2.9.9 redis==5.0.8
COPY server.py /server.py
EXPOSE 8000
ENTRYPOINT ["python3", "/server.py"]
