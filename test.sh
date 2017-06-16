#!/bin/bash
set -o errexit
set -o nounset

IMAGE="$REGISTRY/$REPOSITORY:$TAG"
export IMAGE

bats test
