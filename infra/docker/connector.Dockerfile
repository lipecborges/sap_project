# Imagem do conector on-premise do Raio-X (roda na rede do cliente; só conexão de saída).
# Build a partir da raiz do repositório:
#   docker build -f infra/docker/connector.Dockerfile -t raiox/connector .
ARG NODE_IMAGE=node:22-alpine

FROM ${NODE_IMAGE} AS build
WORKDIR /repo
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @raiox/connector build \
 && pnpm --filter @raiox/connector deploy --legacy --prod /out

FROM ${NODE_IMAGE}
ENV NODE_ENV=production
WORKDIR /app
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /out/package.json ./package.json
COPY --from=build /repo/services/connector/dist ./dist
USER node
CMD ["node", "dist/index.js"]
