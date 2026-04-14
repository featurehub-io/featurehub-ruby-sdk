#!/bin/sh
RACK_ENV=development
if [[ "$1" == "redis" ]]; then
  echo "detected redis"
  export FEATUREHUB_REDIS_STORE=redis://localhost:6379
fi
if [[ "$1" == "memcache" ]]; then
  echo "detected memcache"
  export FEATUREHUB_MEMCACHE_STORE=localhost:11211
fi
if [[ "$1" == "local" ]]; then
  echo "detected local yaml"
  export FEATUREHUB_LOCAL_YAML=feature-flags.yaml
fi
PORT=8099
if [[ "$2" == "sec" ]];  then
  PORT=8100
fi

bundle exec thin -R thin.ru -a 0.0.0.0 -p $PORT start