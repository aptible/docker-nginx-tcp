FROM alpine:3.8

# This can be constant and embedded in the Docker image: it just needs to be
# big enough.
RUN apk add --no-cache openssl \
 && openssl dhparam -out /etc/dhparams.pem 2048

RUN apk add --no-cache ruby curl ruby-json bash

# Install Nginx itself
ADD install-nginx /tmp/
RUN /tmp/install-nginx

ADD bin /usr/local/bin
ADD etc /etc

CMD ["nginx-wrapper"]
