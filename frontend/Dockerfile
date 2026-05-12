# =============================================================
# Stage 1: Builder — build Vite app thành static files
# =============================================================
FROM node:20-alpine AS builder

WORKDIR /app

# Copy package files trước để cache npm install layer
COPY package.json package-lock.json ./

# npm ci: faster + deterministic (dùng package-lock.json chính xác)
RUN npm ci --only=production=false

COPY . .

# Build production bundle
RUN npm run build

# =============================================================
# Stage 2: Runtime — serve static files với Nginx Alpine
# =============================================================
FROM nginx:alpine AS runtime

# Security: chạy Nginx dưới user nginx (non-root)
# nginx:alpine đã có user nginx sẵn (uid 101)

# Copy static files từ builder stage
COPY --from=builder /app/dist /usr/share/nginx/html

# Copy custom Nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

EXPOSE 80

# Healthcheck cho Docker
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -q --spider http://localhost/index.html || exit 1

CMD ["nginx", "-g", "daemon off;"]