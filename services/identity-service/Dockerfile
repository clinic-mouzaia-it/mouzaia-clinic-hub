# ---- Build Stage ----
FROM node:20-alpine AS builder
WORKDIR /app

# Copy workspace manifests for reproducible install
COPY package.json ./
COPY package-lock.json ./

# Copy shared and service manifests
COPY shared/package.json ./shared/package.json
COPY identity-service/package.json ./identity-service/package.json

# Install dependencies for workspace
RUN npm ci || npm install

# Copy tsconfigs and sources
COPY tsconfig.base.json ./tsconfig.base.json
COPY shared ./shared
COPY identity-service/tsconfig.json ./identity-service/tsconfig.json
COPY identity-service/src ./identity-service/src

# Build shared then identity-service
RUN cd shared && npm run build && cd .. \
  && cd identity-service && npm run build && cd ..

# ---- Runtime Stage ----
FROM node:20-alpine AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Copy hoisted production node_modules from builder
COPY --from=builder /app/node_modules ./node_modules

# Copy built artifacts from builder
COPY --from=builder /app/identity-service/dist ./dist

# Ensure @clinic/shared resolves at runtime even if workspace symlinks are pruned
COPY --from=builder /app/shared /app/node_modules/@clinic/shared

## @clinic/shared may also be present in the hoisted node_modules copied above.

# Expose the app port (informational)
EXPOSE 4000

# Run the app
CMD ["node", "dist/index.js"]
