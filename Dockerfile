ARG ELIXIR_VERSION=1.17.3
ARG OTP_VERSION=27.1.2
ARG DEBIAN_VERSION=bullseye-20241111-slim
ARG BUILDER_IMAGE="hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}"
ARG RUNNER_IMAGE="debian:${DEBIAN_VERSION}"

FROM node:20-bullseye-slim AS node_base

FROM ${BUILDER_IMAGE} AS builder

COPY --from=node_base /usr/local/bin/node /usr/local/bin/node
COPY --from=node_base /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
  ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN apt-get update -y && \
  apt-get install -y build-essential git python3 ca-certificates && \
  apt-get clean && rm -f /var/lib/apt/lists/*_*

WORKDIR /app

ENV MIX_ENV=prod
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

RUN mix local.hex --force && \
  mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only $MIX_ENV

RUN mkdir config
COPY config/config.exs config/${MIX_ENV}.exs config/
RUN mix deps.compile

COPY assets/package.json assets/package-lock.json assets/
RUN npm ci --include=dev --prefix assets
RUN npx --prefix assets playwright install chromium

COPY assets assets

COPY priv priv
COPY lib lib
RUN mix compile
RUN mix assets.deploy

COPY config/runtime.exs config/
COPY rel rel

RUN npm prune --omit=dev --prefix assets
RUN mix release

FROM ${RUNNER_IMAGE}

COPY --from=node_base /usr/local/bin/node /usr/local/bin/node
COPY --from=node_base /usr/local/lib/node_modules /usr/local/lib/node_modules
RUN ln -sf ../lib/node_modules/npm/bin/npm-cli.js /usr/local/bin/npm && \
  ln -sf ../lib/node_modules/npm/bin/npx-cli.js /usr/local/bin/npx

RUN apt-get update -y && \
  apt-get install -y \
    ca-certificates \
    curl \
    fonts-liberation \
    libasound2 \
    libatk-bridge2.0-0 \
    libatk1.0-0 \
    libcups2 \
    libdbus-1-3 \
    libdrm2 \
    libgbm1 \
    libgtk-3-0 \
    libncurses5 \
    libnspr4 \
    libnss3 \
    libstdc++6 \
    libx11-xcb1 \
    libxcomposite1 \
    libxdamage1 \
    libxfixes3 \
    libxkbcommon0 \
    libxrandr2 \
    locales \
    openssl \
    tesseract-ocr \
    xdg-utils && \
  apt-get clean && rm -f /var/lib/apt/lists/*_*

RUN sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen && locale-gen

ENV LANG=en_US.UTF-8
ENV LANGUAGE=en_US:en
ENV LC_ALL=en_US.UTF-8
ENV MIX_ENV=prod
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright
ENV INSTABOT_PLAYWRIGHT_PATH=/app/assets/playwright
ENV INSTABOT_BRIDGE_SCRIPT=/app/assets/playwright/dist/playwright_bridge.js
ENV INSTABOT_UPLOADS_DIR=/app/priv/static/uploads
ENV INSTABOT_SCREENSHOT_DIR=/app/priv/static/screenshots

WORKDIR /app
RUN chown nobody /app
RUN mkdir -p assets/playwright/dist assets/node_modules priv/static/uploads priv/static/screenshots && \
  chown -R nobody:root assets priv

COPY --from=builder --chown=nobody:root /ms-playwright /ms-playwright
COPY --from=builder --chown=nobody:root /app/assets/playwright/dist ./assets/playwright/dist
COPY --from=builder --chown=nobody:root /app/assets/node_modules ./assets/node_modules
COPY --from=builder --chown=nobody:root /app/_build/${MIX_ENV}/rel/instabot ./

USER nobody

CMD ["/app/bin/instabot", "start"]
