#!/bin/bash
set -o errexit
set -o nounset

IMAGE="$REGISTRY/$REPOSITORY:$TAG"
export IMAGE

CLIENT_IMAGE="nginx-tcp-test-client"
export CLIENT_IMAGE

(
  cd test/client
  docker build -t "$CLIENT_IMAGE" .
)

bats test
