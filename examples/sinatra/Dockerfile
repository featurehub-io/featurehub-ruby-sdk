FROM ruby:2.7-bullseye

MAINTAINER info@featurehub.io
ENV BUNDLER_VERSION 2.3.15
ARG DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y gnupg

RUN apt-get update && \
    apt-get upgrade -y && \
    apt-get install -y wget tzdata apt-transport-https && \
    apt-get remove -y mysql-common

# set up nsswitch
COPY conf/nsswitch.conf /etc/nsswitch.conf

RUN echo 'gem: --no-document' >> ~/.gemrc && \
    gem update --system 3.0.6 && \
    gem install bundler -v ${BUNDLER_VERSION}  --force

RUN echo "deb https://oss-binaries.phusionpassenger.com/apt/passenger bullseye main" > /etc/apt/sources.list.d/passenger.list

RUN apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xcbcb082a1bb943db 561F9B9CAC40B2F7 && \
    apt-get update && \
    apt-get install -y libnginx-mod-http-passenger=1:6.0.13-1~bullseye1 \
    passenger=1:6.0.13-1~bullseye1 nginx && \
    apt-get clean -y && \
    rm -rf /var/cache/apt/archives/* /var/lib/apt/lists/*
# set up passenger
COPY conf/nginx.conf /etc/nginx/nginx.conf

ENV BUNDLE_PATH /bundle
RUN passenger-config build-native-support

RUN mkdir -p /app/featurehub
COPY Gemfile Gemfile.lock /app/featurehub/
WORKDIR /app/featurehub
RUN cd /app/featurehub && bundle install
ADD . /app/featurehub

CMD /usr/sbin/nginx -g \'daemon off;\'
