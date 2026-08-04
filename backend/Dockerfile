# syntax=docker/dockerfile:1
FROM node:20-alpine

WORKDIR /app

# Copy dependency metadata first so Docker can cache dependency installation.
COPY package*.json ./
RUN npm install --omit=dev && npm cache clean --force

# Copy application source after dependencies.
COPY src ./src

ENV NODE_ENV=production
ENV PORT=5000

EXPOSE 5000

# The official Node image already includes the non-root "node" user.
USER node

CMD ["npm", "start"]
