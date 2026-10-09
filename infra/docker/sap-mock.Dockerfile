# Simulador do add-on ABAP (demos e testes). Não vai para clientes em produção.
ARG NODE_IMAGE=node:22-alpine

FROM ${NODE_IMAGE} AS build
WORKDIR /repo
RUN corepack enable
COPY . .
RUN pnpm install --frozen-lockfile
RUN pnpm --filter @raiox/sap-mock build \
 && pnpm --filter @raiox/sap-mock deploy --legacy --prod /out

FROM ${NODE_IMAGE}
ENV NODE_ENV=production PORT=8000
WORKDIR /app
COPY --from=build /out/node_modules ./node_modules
COPY --from=build /out/package.json ./package.json
COPY --from=build /repo/services/sap-mock/dist ./dist
USER node
EXPOSE 8000
CMD ["node", "dist/index.js"]
