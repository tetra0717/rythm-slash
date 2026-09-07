FROM node:22-alpine
WORKDIR /app
COPY server/package*.json ./server/
RUN cd server && npm ci --omit=dev
COPY server/*.mjs ./server/
COPY build/web/ ./build/web/
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server/index.mjs"]
