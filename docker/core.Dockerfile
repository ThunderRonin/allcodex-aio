FROM node:22-alpine AS builder

RUN corepack enable && corepack prepare pnpm@10.29.3 --activate

WORKDIR /usr/src/app

# Copy allcodex-core workspace files
COPY allcodex-core/package.json allcodex-core/pnpm-lock.yaml allcodex-core/pnpm-workspace.yaml ./
COPY allcodex-core/packages ./packages
COPY allcodex-core/apps/server/package.json ./apps/server/

# Install dependencies (rebuilding better-sqlite3 for alpine)
RUN pnpm install --no-frozen-lockfile

# Copy the rest of the source code
COPY allcodex-core/apps/server ./apps/server
COPY allcodex-core/tsconfig.json ./
COPY allcodex-core/scripts ./scripts

# Build the server app
RUN pnpm server:build

# Production stage
FROM node:22-alpine

# Install runtime dependencies
RUN apk add --no-cache su-exec shadow

WORKDIR /usr/src/app

# Copy the build output
COPY --from=builder /usr/src/app/apps/server/dist /usr/src/app
RUN rm -rf /usr/src/app/node_modules/better-sqlite3
COPY --from=builder /usr/src/app/node_modules/better-sqlite3 /usr/src/app/node_modules/better-sqlite3
COPY allcodex-core/apps/server/start-docker.sh /usr/src/app/

# Add application user
RUN adduser -s /bin/false -D node; exit 0

EXPOSE 8080
CMD [ "sh", "./start-docker.sh" ]
HEALTHCHECK --start-period=10s CMD exec su-exec node node /usr/src/app/docker_healthcheck.cjs
