FROM alpine:3.6

# This can be constant and embedded in the Docker image: it just needs to be
# big enough.
RUN apk add --no-cache openssl \
 && openssl dhparam -out /etc/dhparams.pem 2048

RUN apk add --no-cache ruby ruby-json nginx nginx-mod-stream bash

ADD bin /usr/local/bin
ADD etc /etc

CMD ["nginx-wrapper"]
