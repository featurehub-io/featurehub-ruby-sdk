#!/bin/sh
export FEATUREHUB_EDGE_URL=http://host.docker.internal:8085
docker run --rm -p 8099:8099 --name sinatra --entrypoint "/usr/sbin/nginx"  -e FEATUREHUB_EDGE_URL -e FEATUREHUB_CLIENT_API_KEY docker.io/featurehub/ruby-todo:1.0 -g "daemon off;"