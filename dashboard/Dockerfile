# Multi-stage build for dashboard
FROM node:20-alpine AS builder

WORKDIR /app

# Copy source files
COPY src/ ./src/
COPY public/ ./public/

# Simple static site - just copy files
RUN mkdir -p /dist && cp -r src/* /dist/ && cp -r public/* /dist/ 2>/dev/null || true

# Runtime - using nginx for serving static content
FROM nginx:1.25-alpine

# Copy nginx config
COPY nginx.conf /etc/nginx/conf.d/default.conf

# Copy static files
COPY --from=builder /dist /usr/share/nginx/html

# Security hardening
RUN chown -R nginx:nginx /usr/share/nginx/html && \
    chmod -R 755 /usr/share/nginx/html && \
    chown -R nginx:nginx /var/cache/nginx && \
    chown -R nginx:nginx /var/log/nginx && \
    chown -R nginx:nginx /etc/nginx/conf.d && \
    touch /var/run/nginx.pid && \
    chown -R nginx:nginx /var/run/nginx.pid

USER nginx

EXPOSE 8080

CMD ["nginx", "-g", "daemon off;"]
