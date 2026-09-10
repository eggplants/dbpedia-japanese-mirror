FROM alpine:3.20@sha256:d9e853e87e55526f6b2917df91a2115c36dd7c696a35be12163d44e6e2a4b6bc

RUN apk add --no-cache bash ca-certificates coreutils curl grep bzip2 pigz

COPY download.sh /download.sh
RUN chmod +x /download.sh

ENTRYPOINT ["/bin/bash", "/download.sh"]
