FROM debian:10.5 AS builder

RUN apt update && apt install -y \
    build-essential \
    git \
    libsqlite3-dev \
    zlib1g-dev

RUN cd /tmp && \
    git clone https://github.com/mapbox/tippecanoe.git && \
    cd tippecanoe && \
    make


FROM debian:10.5

COPY --from=builder /tmp/tippecanoe/tippecanoe /usr/bin/tippecanoe
COPY --from=builder /tmp/tippecanoe/tile-join /usr/bin/tile-join

RUN apt update && apt install -y \
    wget \
    python3-pyosmium \
    osmium-tool \
    ruby \
    curl

WORKDIR /data
VOLUME /data
