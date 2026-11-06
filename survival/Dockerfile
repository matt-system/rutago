FROM node:22-alpine
WORKDIR /app
COPY server.mjs ./server.mjs
COPY web ./web
EXPOSE 8788
CMD ["node","server.mjs"]