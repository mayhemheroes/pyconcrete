#!/usr/bin/env bash

set -ex

PORT=${PORT:="5151"}

declare -xr REPO_ROOT=$( cd "$( dirname "${BASH_SOURCE[0]}" )/../" && pwd )

cd ${REPO_ROOT}

docker build \
    -t falldog/example-django \
    -f example/django/Dockerfile \
    .

echo "Django testing website running at http://127.0.0.1:${PORT}"
docker run \
    --rm \
    -p ${PORT}:80 \
    --name pyconcrete-example-django \
    falldog/example-django
