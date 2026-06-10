FROM oven/bun:1-alpine AS builder

WORKDIR /usr/src/app

COPY allcodex-portal/package.json allcodex-portal/bun.lock ./
RUN bun install --frozen-lockfile

COPY allcodex-portal ./
RUN bun run build

FROM oven/bun:1-alpine

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/package.json ./
COPY --from=builder /usr/src/app/bun.lock ./
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/.next ./.next
COPY --from=builder /usr/src/app/public ./public
COPY --from=builder /usr/src/app/next.config.ts ./

EXPOSE 3000
CMD [ "bun", "run", "start" ]
