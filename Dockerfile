ARG ELIXIR_VERSION=1.18.2-erlang-27.2.1-alpine-3.21.2


FROM docker.io/hexpm/elixir:${ELIXIR_VERSION} AS build
ARG PIX_VERSION
ENV PIX_VERSION=${PIX_VERSION}
# ERL_FLAGS="+JPperf true" is a workaround to "fix" the problem of docker cross-platform builds via QEMU.
# REF:  https://elixirforum.com/t/mix-deps-get-memory-explosion-when-doing-cross-platform-docker-build/57157
ENV ERL_FLAGS="+JPperf true"
WORKDIR /code
RUN apk add --no-cache git build-base
COPY mix.exs ./
COPY mix.lock ./
RUN mix deps.get --check-locked
RUN mix deps.unlock --check-unused
COPY config ./config
COPY lib ./lib
COPY test ./test
RUN mix compile --warnings-as-errors
COPY .formatter.exs ./
RUN mix format --check-formatted
COPY .credo.exs ./
RUN mix credo --strict --all
RUN mix escript.build


FROM docker.io/hexpm/elixir:${ELIXIR_VERSION}
RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    docker-cli \
    docker-cli-buildx \
    git
COPY --from=build /code/pix /usr/local/pix
ENTRYPOINT ["/usr/local/bin/pix"]
