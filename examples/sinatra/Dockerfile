FROM phusion/passenger-ruby33:latest

MAINTAINER info@featurehub.io
ENV BUNDLER_VERSION 2.3.15
ARG DEBIAN_FRONTEND=noninteractive

RUN echo 'gem: --no-document' >> ~/.gemrc && \
    gem update --system && \
    gem install bundler -v ${BUNDLER_VERSION}  --force


# set up nsswitch
COPY examples/sinatra/conf/nsswitch.conf /etc/nsswitch.conf

COPY examples/sinatra/conf/nginx.conf /etc/nginx/nginx.conf
ADD . /app/featurehub
WORKDIR /app/featurehub
RUN cd examples/sinatra && bundle config set --local deployment 'true' --without 'development test' path 'vendor/bundle' frozen true
RUN bundle install
ENV BUNDLE_PATH=/app/featurehub/examples/sinatra/vendor/bundle

CMD /usr/sbin/nginx -g 'daemon off;'
#CMD /usr/bin/bash
