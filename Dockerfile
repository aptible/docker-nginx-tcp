FROM alpine:3.6

RUN apk add --no-cache ruby ruby-json nginx nginx-mod-stream bash

ADD bin /usr/local/bin
ADD etc /etc

CMD ["nginx-wrapper"]
