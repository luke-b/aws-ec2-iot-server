FROM python:3.11-slim
WORKDIR /app
COPY iotdb_adapter.py /app/iotdb_adapter.py
ENV IOTDB_ADAPTER_PORT=8089
EXPOSE 8089
CMD ["python", "/app/iotdb_adapter.py"]
