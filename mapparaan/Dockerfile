FROM python:3.12-slim
WORKDIR /app
# Only what the API needs. data/raw, data/build and the Flutter app stay out of the image.
COPY backend/planner/ backend/planner/
COPY data/gtfs/ data/gtfs/
COPY data/reference/ data/reference/
ENV PYTHONUNBUFFERED=1
EXPOSE 8080
# api.py reads PORT from the environment (the host sets it) and refuses to bind
# beyond localhost unless MAPPARAAN_ALLOWED_ORIGINS is set (see render.yaml).
CMD ["python", "backend/planner/api.py", "--host", "0.0.0.0", "--data-dir", "/app/data"]