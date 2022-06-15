#!/bin/sh
RACK_ENV=development
bundle exec thin -R config.ru -a 0.0.0.0 -p 8099 start