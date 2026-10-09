# Imagem única da API Raio-X (com a web embutida), usada no Cloud e no Self-hosted.
# Build a partir da raiz do repositório:
#   docker build -f infra/docker/api.Dockerfile -t raiox/api .
ARG NODE_IMAGE=node:22-alpine

FROM ${NODE_IMAGE} AS build
WORKDIR /repo
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @raiox/web build \
 && pnpm --filter @raiox/api build \
 && pnpm --filter @raiox/api deploy --legacy --prod /out

FROM ${NODE_IMAGE}
ENV NODE_ENV=production \
    PORT=3000 \
    WEB_DIST_DIR=/app/web
WORKDIR /app
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /out/package.json ./package.json
COPY --from=build /repo/services/api/dist ./dist
COPY --from=build /repo/apps/web/dist ./web
USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=5s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/api/health || exit 1
CMD ["node", "dist/index.js"]
