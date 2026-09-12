FROM alpine:3.24@sha256:28bd5fe8b56d1bd048e5babf5b10710ebe0bae67db86916198a6eec434943f8b

RUN apk add --no-cache bash ca-certificates coreutils curl grep sed bzip2 pigz

COPY download.sh /download.sh
RUN chmod +x /download.sh

ENTRYPOINT ["/bin/bash", "/download.sh"]
