# ---- Build Stage ----
FROM node:20-alpine AS builder
WORKDIR /app

# Copy workspace manifests for reproducible install
COPY package.json ./
COPY package-lock.json ./

# Copy shared and service manifests for efficient install
COPY shared/package.json ./shared/package.json
COPY pharmacy-service/package.json ./pharmacy-service/package.json

# Install dependencies for workspace
RUN npm ci || npm install

# Copy tsconfigs and sources
COPY tsconfig.base.json ./tsconfig.base.json
COPY shared ./shared
COPY pharmacy-service/tsconfig.json ./pharmacy-service/tsconfig.json
COPY pharmacy-service/src ./pharmacy-service/src

# Build shared then service
RUN cd shared && npm run build && cd .. \
  && cd pharmacy-service && npm run build && cd ..

# ---- Runtime Stage ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Copy hoisted production node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy built artifacts from builder
COPY --from=builder /app/pharmacy-service/dist ./dist

# Ensure @clinic/shared resolves at runtime even if workspace symlinks are pruned
COPY --from=builder /app/shared /app/node_modules/@clinic/shared

EXPOSE 4100
CMD ["node", "dist/index.js"]
