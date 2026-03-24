# Stage 1: Builder
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci

COPY . .

RUN npx prisma generate
RUN npm run build

# Stage 2: Runner
FROM node:20-alpine AS runner

ENV NODE_ENV=production

WORKDIR /app

# Copy standalone output
COPY --from=builder /app/.next/standalone ./
# Copy static files
COPY --from=builder /app/.next/static ./.next/static
# Copy public folder
COPY --from=builder /app/public ./public
# Copy prisma files for migrations
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/node_modules/.prisma ./node_modules/.prisma
COPY --from=builder /app/node_modules/@prisma ./node_modules/@prisma

EXPOSE 3000

CMD ["sh", "-c", "npx prisma migrate deploy && node server.js"]
