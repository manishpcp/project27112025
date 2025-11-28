FROM node:18-alpine

# Install curl for ECS health check
RUN apk add --no-cache curl

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production && npm cache clean --force

COPY app.js .

RUN addgroup -g 1001 -S nodejs && \
    adduser -S nodejs -u 1001 && \
    chown -R nodejs:nodejs /app

USER nodejs

EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=5s --start-period=40s --retries=3 \
  CMD curl -f http://localhost:3000/health || exit 1

CMD ["node", "app.js"]
