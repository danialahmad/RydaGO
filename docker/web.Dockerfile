# Builds the Flutter web app and serves it with nginx. Build context is the repo root.
#
# Flutter is installed from its git tag so the version matches pubspec.lock exactly
# (keep FLUTTER_VERSION in step with `flutter --version` on your machine).

FROM debian:bookworm-slim AS build
ARG FLUTTER_VERSION=3.47.7
RUN apt-get update \
 && apt-get install -y --no-install-recommends git curl ca-certificates unzip xz-utils \
 && rm -rf /var/lib/apt/lists/*
RUN git clone --depth 1 --branch ${FLUTTER_VERSION} https://github.com/flutter/flutter.git /opt/flutter
ENV PATH="/opt/flutter/bin:${PATH}"
# Flutter refuses to run as root inside some images unless told this is fine.
ENV FLUTTER_ALLOW_ROOT=true
RUN flutter config --no-analytics --enable-web \
 && flutter precache --web

WORKDIR /app
# Dependencies first so they stay cached until pubspec changes.
COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get
COPY analysis_options.yaml ./
COPY lib ./lib
COPY web ./web
# No service worker: it kept serving the previous build until a second reload.
RUN flutter build web --release --pwa-strategy=none

FROM nginx:1.27-alpine
COPY docker/nginx.conf /etc/nginx/conf.d/default.conf
COPY --from=build /app/build/web /usr/share/nginx/html
EXPOSE 80
