#!/bin/sh
RACK_ENV=development
export FEATUREHUB_REDIS_STORE=redis://localhost:6379
bundle exec thin -R thin.ru -a 0.0.0.0 -p 8099 start