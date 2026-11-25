# Contexto de build: raíz del repo (make build-services)
FROM python:3.12-slim
WORKDIR /app
COPY services/autorizacion-svc/app.py .
EXPOSE 8080
CMD ["python", "app.py"]
