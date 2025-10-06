# Multi-stage Dockerfile for identity-service
# Builder stage

# ---- Build Stage ----
FROM node:20-alpine AS builder
WORKDIR /app

# Install dependencies
COPY package*.json ./
RUN npm ci || npm install

# Copy source and build
COPY tsconfig.json ./
COPY src ./src
RUN npm run build

# ---- Runtime Stage ----
FROM node:20-alpine
WORKDIR /app


# Copy package files and install only prod deps
COPY package*.json ./
RUN npm ci --omit=dev || npm install --omit=dev

# Copy compiled output from builder
COPY --from=builder /app/dist ./dist

# Expose the app port (from env, default 4000)
EXPOSE 4000

# Run the app
CMD ["node", "dist/index.js"]
