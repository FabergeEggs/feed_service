ARG ELIXIR_VERSION=1.18.4
ARG OTP_VERSION=27.3.4
ARG DEBIAN_VERSION=bookworm-20260406

FROM hexpm/elixir:${ELIXIR_VERSION}-erlang-${OTP_VERSION}-debian-${DEBIAN_VERSION}-slim AS builder

ENV MIX_ENV=prod \
    LANG=C.UTF-8

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      build-essential \
      cmake \
      git \
      ca-certificates \
      pkg-config \
 && rm -rf /var/lib/apt/lists/*

RUN mix local.hex --force --if-missing \
 && mix local.rebar --force --if-missing

WORKDIR /app

COPY mix.exs mix.lock ./
COPY config config
RUN mix deps.get --only $MIX_ENV \
 && mix deps.compile

COPY priv priv
COPY lib lib
COPY rel rel

RUN mix compile \
 && mix release

ARG DEBIAN_VERSION

FROM debian:${DEBIAN_VERSION}-slim AS runtime

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8 \
    PHX_SERVER=true \
    PORT=4000

RUN apt-get update -qq \
 && apt-get install -y --no-install-recommends \
      ca-certificates \
      libstdc++6 \
      libncurses6 \
      locales \
      openssl \
      curl \
 && rm -rf /var/lib/apt/lists/* \
 && sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen \
 && locale-gen

WORKDIR /app

RUN groupadd --system app \
 && useradd --system --gid app --home /app --shell /usr/sbin/nologin app \
 && chown app:app /app

USER app

COPY --from=builder --chown=app:app /app/_build/prod/rel/feed_service ./

USER root

RUN apt-get update -qq && apt-get install -y --no-install-recommends dos2unix \
 && find /app/bin -type f -exec dos2unix {} \; \
 && apt-get remove -y dos2unix && apt-get autoremove -y && rm -rf /var/lib/apt/lists/*

RUN chmod +x /app/bin/migrate /app/bin/server /app/bin/entrypoint
USER app

EXPOSE 4000

HEALTHCHECK --interval=10s --timeout=5s --retries=5 \
  CMD curl -fsS http://localhost:${PORT}/api/v1/health || exit 1

ENTRYPOINT ["/app/bin/entrypoint"]
