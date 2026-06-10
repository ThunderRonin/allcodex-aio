FROM node:22-alpine AS builder

WORKDIR /usr/src/app

COPY allcodex-portal/package.json allcodex-portal/package-lock.json ./
# Clean install dependencies
RUN npm ci

COPY allcodex-portal ./
RUN npm run build

FROM node:22-alpine

WORKDIR /usr/src/app

COPY --from=builder /usr/src/app/package.json ./
COPY --from=builder /usr/src/app/package-lock.json ./
COPY --from=builder /usr/src/app/node_modules ./node_modules
COPY --from=builder /usr/src/app/.next ./.next
COPY --from=builder /usr/src/app/public ./public
COPY --from=builder /usr/src/app/next.config.ts ./

EXPOSE 3000
CMD [ "npm", "run", "start" ]
