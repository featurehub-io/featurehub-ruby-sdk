FROM ruby:3.3.10-bookworm

MAINTAINER info@featurehub.io
ENV BUNDLER_VERSION 2.3.15
ARG DEBIAN_FRONTEND=noninteractive

RUN apt update && \
    apt install -y gnupg wget tzdata apt-transport-https dirmngr gnupg curl && \
    curl https://oss-binaries.phusionpassenger.com/auto-software-signing-gpg-key-2025.txt | gpg --dearmor | tee /etc/apt/trusted.gpg.d/phusion.gpg >/dev/null && \
        sh -c 'echo deb https://oss-binaries.phusionpassenger.com/apt/passenger bookworm main > /etc/apt/sources.list.d/passenger.list' && \
        apt-get update && \
        apt-get install -y nginx passenger

#ENV BUNDLE_PATH /bundle
RUN passenger-config build-native-support

RUN echo 'gem: --no-document' >> ~/.gemrc && \
    gem update --system && \
    gem install bundler -v ${BUNDLER_VERSION}  --force

# set up nsswitch
COPY examples/sinatra/conf/nsswitch.conf /etc/nsswitch.conf

RUN mkdir -p /app/featurehub
COPY examples/sinatra/conf/nginx.conf /etc/nginx/nginx.conf
COPY . /app/
WORKDIR /app/featurehub
RUN cd /app/featurehub && bundle install
ADD examples/sinatra/ /app/featurehub

CMD /usr/sbin/nginx -g \'daemon off;\'
