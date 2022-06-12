#!/bin/sh
RACK_ENV=development
CANONICAL_HOST=0.0.0.0
bundle exec thin -R config.ru -a 0.0.0.0 -p 3000 start