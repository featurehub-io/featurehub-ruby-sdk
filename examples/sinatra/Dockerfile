FROM phusion/passenger-ruby33:latest

MAINTAINER info@featurehub.io
ENV BUNDLER_VERSION 4.0.3
ARG DEBIAN_FRONTEND=noninteractive

# The purpose of this Dockerfile is to build a test to-do server that can be used against the
# e2e tests. It *MUST* test the SDK on the current HEAD, so the file is complicated and awkward
# and not like a typical deploy.

RUN echo 'gem: --no-document' >> ~/.gemrc && \
    gem update --system && \
    gem install bundler -v ${BUNDLER_VERSION}  --force

RUN gem uninstall logger -v 1.6.0

# set up nsswitch
COPY examples/sinatra/conf/nsswitch.conf /etc/nsswitch.conf

COPY examples/sinatra/conf/nginx.conf /etc/nginx/nginx.conf
ADD . /app/featurehub
WORKDIR /app/featurehub
RUN rm Gemfile Gemfile.lock && cd examples/sinatra && bundle config set --local deployment 'true' --without 'development test' path 'vendor/bundle'
RUN cd /app/featurehub/examples/sinatra && cat .bundle/config && mkdir logs
RUN cd /app/featurehub/examples/sinatra && bundle install
RUN chown -R nobody /app
ENV BUNDLE_PATH=/app/featurehub/examples/sinatra/vendor/bundle

USER root
CMD /usr/sbin/nginx -g 'daemon off;'
#CMD /usr/bin/bash
