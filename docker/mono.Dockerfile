##################################################################################
FROM node:24-trixie AS node

COPY repos/lila /lila
COPY conf/mono.conf /lila/conf/mono.conf
ENV COREPACK_ENABLE_DOWNLOAD_PROMPT=0
ENV COREPACK_INTEGRITY_KEYS=0
RUN corepack enable \
# --prod chứ KHÔNG --debug: --debug nướng site.debug=true vào bundle, làm MỌI unhandled
# rejection hiện dialog lỗi cho người dùng thật (David dính trên iOS 03/08).
    && /lila/ui/build --clean --prod

##################################################################################
FROM mongo:7-jammy AS dbbuilder

RUN apt update \
    && apt install -y \
        curl \
        python3-pip \
        python3-venv \
    && apt clean \
    && pip3 install faker pymongo requests

ENV JAVA_HOME=/opt/java/openjdk
COPY --from=eclipse-temurin:25-jdk $JAVA_HOME $JAVA_HOME
ENV PATH="${JAVA_HOME}/bin:${PATH}"

COPY repos/lila /lila
COPY repos/lila-db-seed /lila-db-seed
COPY scripts/reset-db.sh /scripts/reset-db.sh
COPY scripts/seed-once.sh /scripts/seed-once.sh
RUN chmod +x /scripts/reset-db.sh /scripts/seed-once.sh
WORKDIR /lila-db-seed

RUN mkdir /seeded \
    && mongod --fork --logpath /var/log/mongodb/mongod.log --dbpath /seeded \
    && /scripts/reset-db.sh

##################################################################################
FROM sbtscala/scala-sbt:eclipse-temurin-25.0.3_9_1.12.13_3.8.4 AS lilawsbuilder

COPY repos/lila-ws /lila-ws
WORKDIR /lila-ws
# Retry: `sbt stage` thỉnh thoảng exit 1 do coursier tải phụ thuộc lỗi tạm thời trên
# runner CI (không tất định — cùng commit lúc pass lúc fail). Thử lại tối đa 3 lần trong
# CÙNG layer để khỏi phải re-dispatch cả workflow. Chỉ fail build nếu cả 3 lần đều hỏng.
RUN sbt stage || (sleep 5 && sbt stage) || (sleep 15 && sbt stage)

##################################################################################
FROM sbtscala/scala-sbt:eclipse-temurin-25.0.3_9_1.12.13_3.8.4 AS lilafishnetbuilder

COPY repos/lila-fishnet /lila-fishnet
WORKDIR /lila-fishnet
# Retry (xem ghi chú ở stage lila-ws): stage này đã fail 4 lần liên tiếp 05/08 do coursier
# tải phụ thuộc lỗi tạm thời (exit 1 câm ngay sau warning, kèm ^[[0J), dù cùng commit đã
# build thành công lúc 11:58. Thử lại tối đa 3 lần trong cùng layer.
RUN sbt app/stage || (sleep 5 && sbt app/stage) || (sleep 15 && sbt app/stage)

##################################################################################
FROM sbtscala/scala-sbt:eclipse-temurin-25.0.3_9_1.12.13_3.8.4 AS lilabuilder

COPY --from=node /lila /lila
WORKDIR /lila
RUN TZ=UTC git log -1 --date=iso-strict-local --pretty='format:app.version.commit = "%H"%napp.version.date = "%ad"%napp.version.message = """%s"""%n' | tee conf/version.conf
# Retry (xem ghi chú ở stage lila-ws): coursier tải phụ thuộc lỗi tạm thời trên CI.
RUN ./lila.sh stage || (sleep 5 && ./lila.sh stage) || (sleep 15 && ./lila.sh stage)

##################################################################################
FROM mongo:7-jammy

RUN apt update \
    && apt install -y debian-keyring debian-archive-keyring apt-transport-https curl \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/gpg.key' | gpg --dearmor -o /usr/share/keyrings/caddy-stable-archive-keyring.gpg \
    && curl -1sLf 'https://dl.cloudsmith.io/public/caddy/stable/debian.deb.txt' | tee /etc/apt/sources.list.d/caddy-stable.list \
    && apt update \
    && apt install -y \
        caddy \
        curl \
        python3-pip \
        redis \
        supervisor \
    && apt clean \
    && pip3 install \
        berserk \
        faker \
        pymongo \
        pytest \
        requests \
    && mkdir -p /var/log/supervisor

COPY --from=dbbuilder /lila-db-seed /lila-db-seed
COPY --from=dbbuilder /scripts /scripts
COPY --from=dbbuilder /seeded /seeded
COPY --from=lilawsbuilder /lila-ws/target /lila-ws/target
COPY --from=lilafishnetbuilder /lila-fishnet/app/target /lila-fishnet/app/target
# The upstream fishnet binary is built against musl and ships its own Stockfish, so it
# needs nothing here but its loader. Copying that is far smaller than a second runtime.
# Glob `ld-musl-*.so.1` thay vì hardcode `-x86_64`: tên loader khác theo kiến trúc
# (x86_64 vs aarch64), hardcode làm build multi-arch VỠ ở nhánh arm64 (audit 22/08 —
# đúng lỗi khiến build đa-kiến-trúc lâu nay hỏng). Mỗi nhánh build chỉ có đúng một
# file khớp glob (loader của chính kiến trúc đó).
COPY --from=niklasf/fishnet:2.12.0 /fishnet /usr/local/bin/fishnet
COPY --from=niklasf/fishnet:2.12.0 /lib/ld-musl-*.so.1 /lib/
COPY --from=lilabuilder /lila/bin/mongodb/indexes.js /lila/bin/mongodb/indexes.js
COPY --from=lilabuilder /lila/target /lila/target
COPY --from=lilabuilder /lila/public /lila/public
COPY --from=lilabuilder /lila/conf   /lila/conf
COPY --from=node /lila/public /lila/target/universal/stage/public

COPY conf/supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY conf/mono.Caddyfile /mono.Caddyfile
COPY static /static

ENV JAVA_HOME=/opt/java/openjdk
ENV JAVA_OPTS="-Xms4g -Xmx4g"
ENV PATH="${JAVA_HOME}/bin:${PATH}"
ENV LANG=C.utf8
COPY --from=eclipse-temurin:25-jdk $JAVA_HOME $JAVA_HOME

ENV LILA_SITE_NAME=lila-quick
ENV LILA_DOMAIN=localhost:8080
ENV LILA_URL=http://localhost:8080

CMD ["supervisord", "-c", "/etc/supervisor/supervisord.conf"]
