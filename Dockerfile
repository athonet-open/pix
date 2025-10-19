ARG ELIXIR_VERSION=1.18.4-erlang-27.3.4-alpine-3.21.3


FROM docker.io/hexpm/elixir:${ELIXIR_VERSION} AS bootstrap
ARG VERSION
ENV VERSION=${VERSION}
# ERL_FLAGS="+JPperf true" is a workaround to "fix" the problem of docker cross-platform builds via QEMU.
# REF:  https://elixirforum.com/t/mix-deps-get-memory-explosion-when-doing-cross-platform-docker-build/57157
ENV ERL_FLAGS="+JPperf true"
ENV MIX_ENV=prod
WORKDIR /code
RUN apk add --no-cache git build-base
COPY mix.exs ./
COPY mix.lock ./
COPY config ./config
COPY lib ./lib
COPY shell_completions ./shell_completions
RUN mix deps.get
RUN mix compile --warnings-as-errors
RUN mix escript.build


FROM docker.io/hexpm/elixir:${ELIXIR_VERSION} AS pix
RUN apk add --no-cache bash ca-certificates coreutils docker-cli docker-cli-buildx git tar
RUN git config --global --add safe.directory "*"
COPY --from=bootstrap /code/pix /usr/local/bin/pix
ENTRYPOINT ["/usr/local/bin/pix"]
