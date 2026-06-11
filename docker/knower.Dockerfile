FROM oven/bun:1 AS builder

WORKDIR /usr/src/app

# Copy allknower project files
COPY allknower/package.json allknower/bun.lock ./
COPY allknower/prisma ./prisma
COPY allknower/patches ./patches

# Install dependencies (this builds Prisma client and LanceDB for glibc)
RUN bun install --frozen-lockfile
RUN bunx prisma generate

# Copy allknower source files
COPY allknower/src ./src
COPY allknower/tsconfig.json ./

# Build allknower app
RUN bun run build

# Runner stage
FROM oven/bun:1

WORKDIR /usr/src/app

# Copy built app
COPY --from=builder /usr/src/app/dist ./dist
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/prisma ./prisma
COPY allknower/package.json ./

EXPOSE 3001
CMD [ "sh", "-c", "bunx prisma migrate deploy && bun dist/index.js" ]
