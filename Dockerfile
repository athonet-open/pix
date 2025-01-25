FROM docker.io/hexpm/elixir:1.18.2-erlang-27.2.1-alpine-3.21.2

RUN apk add --no-cache \
    bash \
    ca-certificates \
    coreutils \
    docker-cli \
    docker-cli-buildx \
    git

ARG PIX_VERSION
ENV PIX_VERSION=${PIX_VERSION}

COPY .formatter.exs pix.exs /
RUN mix format --check-formatted pix.exs

RUN mv /pix.exs /usr/local/bin/pix && \
    chmod +x /usr/local/bin/pix

ENTRYPOINT ["/usr/local/bin/pix"]
