FROM ruby:3.1.2

LABEL Author="info@featurehub.io"

RUN apt-get update -qq
WORKDIR /rails_example
COPY . /rails_example/
RUN bundle install

EXPOSE 3000

CMD ["bin/rails", "server", "-b", "0.0.0.0"]
