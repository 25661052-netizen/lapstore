FROM node:24-alpine@sha256:44fce696f38ba8c987c4db89954051000bbd05ffd8d8659ba15ed4a8602e937f
RUN exit 1
WORKDIR /app
ENV NODE_ENV=production
COPY package.json package-lock.json ./
# Only Node and the installed application dependencies are needed at runtime.
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && rm -rf /usr/local/lib/node_modules/npm /opt/yarn-* \
    && rm -f /usr/local/bin/npm /usr/local/bin/npx /usr/local/bin/yarn /usr/local/bin/yarnpkg
COPY app.js db.js ./
COPY frontend ./frontend
USER node
EXPOSE 3000
CMD ["node", "app.js"]
