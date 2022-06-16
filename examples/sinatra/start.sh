#!/bin/sh
RACK_ENV=development
bundle exec thin -R thin.ru -a 0.0.0.0 -p 8099 start