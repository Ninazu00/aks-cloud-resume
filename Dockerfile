# Stage 1 — install dependencies
FROM node:latest AS builder
WORKDIR /app/backend
COPY backend/package*.json ./
RUN npm ci --omit=dev

# Stage 2 — lean runtime image (no npm)
FROM node:latest
WORKDIR /app
COPY --from=builder /app/backend/node_modules ./backend/node_modules
COPY backend/server.js ./backend/server.js
COPY frontend/ ./frontend/
EXPOSE 3000
USER node
CMD ["node", "backend/server.js"]