FROM node:20-alpine

WORKDIR /app

COPY package.json ./
RUN npm install --omit=dev && npm cache clean --force

COPY --chown=node:node src ./src

USER node

EXPOSE 5000

CMD ["npm", "start"]
