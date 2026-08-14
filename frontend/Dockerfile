# Stage 1: build the React app
FROM node:20-alpine AS build

WORKDIR /app

COPY package.json ./
RUN npm install

COPY index.html ./
COPY src ./src

RUN npm run build

# Stage 2: serve static assets with nginx and proxy /api to backend
FROM nginx:1.27-alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/dist /usr/share/nginx/html

EXPOSE 80

CMD ["nginx", "-g", "daemon off;"]
