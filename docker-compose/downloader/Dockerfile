FROM alpine:3.24@sha256:be2656061b536c1883c4034790e21d0a09c5aaaf51968b89368a3c0371ea2c9a

RUN apk add --no-cache bash ca-certificates coreutils curl grep sed bzip2 pigz

COPY download.sh /download.sh
RUN chmod +x /download.sh

ENTRYPOINT ["/bin/bash", "/download.sh"]
