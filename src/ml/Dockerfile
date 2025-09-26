# Production-ready Docker image for Real-Time Scoring API
FROM node:18-alpine

LABEL maintainer="Azure ML Infrastructure Team"
LABEL description="Real-Time Scoring API for Azure ML Fabric Demo"

# Set working directory
WORKDIR /app

# Create non-root user for security
RUN addgroup -g 1001 -S nodejs
RUN adduser -S scoring -u 1001

# Copy package files
COPY package*.json ./

# Install dependencies
RUN npm ci --only=production && npm cache clean --force

# Copy application source
COPY src/ ./src/

# Set ownership to non-root user
RUN chown -R scoring:nodejs /app
USER scoring

# Expose the scoring API port
EXPOSE 8080

# Health check
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:8080/health || exit 1

# Set environment variables
ENV NODE_ENV=production
ENV PORT=8080

# Start the API server
CMD ["node", "src/ml/scoring-api-server.js"]