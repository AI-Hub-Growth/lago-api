# syntax=lincanvas-registry.cn-hangzhou.cr.aliyuncs.com/lincanvas/dockerfile:1.25

ARG PDFCPU_VERSION=0.11.1
ARG GO_VERSION=1.25.8

FROM lincanvas-registry.cn-hangzhou.cr.aliyuncs.com/lincanvas/golang:${GO_VERSION} AS pdfcpu-build

ARG PDFCPU_VERSION
ENV GOPROXY=https://mirrors.aliyun.com/goproxy/,direct

RUN go install github.com/pdfcpu/pdfcpu/cmd/pdfcpu@v${PDFCPU_VERSION}

FROM lincanvas-registry.cn-hangzhou.cr.aliyuncs.com/lincanvas/ruby:4.0.2-slim AS build

ARG BUNDLE_WITH

WORKDIR /app

RUN sed -i 's|http://deb.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
  apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y nodejs curl build-essential git pkg-config libpq-dev libclang-dev postgresql-client libyaml-dev && \
  rm -rf /var/lib/apt/lists/*

ENV RUSTUP_UPDATE_ROOT=https://mirrors.aliyun.com/rustup/rustup
ENV RUSTUP_DIST_SERVER=https://mirrors.aliyun.com/rustup
RUN curl --proto '=https' --tlsv1.2 -sSf https://mirrors.aliyun.com/repo/rust/rustup-init.sh | sh -s -- -y && \
  printf '%s\n' \
    '[source.crates-io]' \
    "replace-with = 'aliyun'" \
    '[source.aliyun]' \
    'registry = "sparse+https://mirrors.aliyun.com/crates.io-index/"' \
    > /root/.cargo/config.toml

COPY ./Gemfile /app/Gemfile
COPY ./Gemfile.lock /app/Gemfile.lock

ENV BUNDLER_VERSION='4.0.4'
ENV PATH="$PATH:/root/.cargo/bin/"
RUN gem sources --remove https://rubygems.org/ && \
  gem sources --add https://mirrors.aliyun.com/rubygems/ && \
  gem install bundler --no-document -v '4.0.4' && \
  bundle config set --global mirror.https://rubygems.org https://mirrors.aliyun.com/rubygems/

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"
RUN --mount=type=secret,id=BUNDLE_GEMS__CONTRIBSYS__COM,env=BUNDLE_GEMS__CONTRIBSYS__COM \
  bundle config set build.nokogiri --use-system-libraries &&\
  bundle install --jobs=3 --retry=3

FROM lincanvas-registry.cn-hangzhou.cr.aliyuncs.com/lincanvas/ruby:4.0.2-slim

ARG BUNDLE_WITH

RUN sed -i 's|http://deb.debian.org|https://mirrors.aliyun.com|g' /etc/apt/sources.list.d/debian.sources && \
  apt-get update && \
  apt-get upgrade -y && \
  apt-get install -y git libpq-dev curl postgresql-client libjemalloc2 && \
  rm -rf /var/lib/apt/lists/*

ENV LD_PRELOAD=libjemalloc.so.2

ARG SEGMENT_WRITE_KEY
ARG GOCARDLESS_CLIENT_ID
ARG GOCARDLESS_CLIENT_SECRET

ENV SEGMENT_WRITE_KEY=$SEGMENT_WRITE_KEY
ENV GOCARDLESS_CLIENT_ID=$GOCARDLESS_CLIENT_ID
ENV GOCARDLESS_CLIENT_SECRET=$GOCARDLESS_CLIENT_SECRET

ENV BUNDLE_WITH=${BUNDLE_WITH:-}
ENV BUNDLE_WITHOUT="development test"

COPY --from=build /usr/local/bundle/ /usr/local/bundle
COPY --from=pdfcpu-build /go/bin/pdfcpu /usr/local/bin/pdfcpu
WORKDIR /app
COPY . .

CMD ["./scripts/start.sh"]
