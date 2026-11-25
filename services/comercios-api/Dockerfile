# Contexto de build: raíz del repo (make build-services)
FROM python:3.12-slim
WORKDIR /app
COPY services/comercios-api/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY services/comercios-api/app.py .
COPY schemas/merchant-state.avsc /app/merchant-state.avsc
EXPOSE 8080
CMD ["python", "app.py"]
