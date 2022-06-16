# Official FeatureHub Ruby SDK.

## Overview
To control the feature flags from the FeatureHub Admin console, either use our [demo](https://demo.featurehub.io) version for evaluation or install the app using our guide [here](https://docs.featurehub.io/featurehub/latest/installation.html)

## SDK installation

Add the featurehub sdk gem to your Gemfile and/or gemspec if you are creating a library:

```
gem `featurehub-sdk`
```

               
To use it in your code, use:

```ruby
require 'featurehub-sdk'
```

## Options to get feature updates

There are 2 ways to request for feature updates via this SDK:

- **SSE (Server Sent Events) realtime updates mechanism**

  In this mode, you will make a connection to the FeatureHub Edge server using using Server Sent Events, any updates to any features will come through in _near realtime_, automatically updating the feature values in the repository. This method is recommended for server applications.

- **FeatureHub polling client (GET request updates)**

  In this mode you can set an interval (from 0 - just once) to any number of seconds between polling. This is more useful for when you have short term single threaded
  processes like command line tools. Batch tools that iterate over data sets and wish to control when updates happen can also benefit from this method.

This SDK uses concurrent ruby to ensure whichever option you choose stays open and continually updates your data.

## Example

Check our example Sinatra app [here](https://github.com/featurehub-io/featurehub-ruby-sdk/tree/main/example/sinatra)

## Quick start

### Connecting to FeatureHub
There are 3 steps to connecting:
1) Copy FeatureHub API Key from the FeatureHub Admin Console
2) Create FeatureHub config
3) Check FeatureHub Repository readiness and request feature state

#### 1. API Key from the FeatureHub Admin Console
Find and copy your API Key from the FeatureHub Admin Console on the API Keys page -
you will use this in your code to configure feature updates for your environments.
It should look similar to this: ```default/71ed3c04-122b-4312-9ea8-06b2b8d6ceac/fsTmCrcZZoGyl56kPHxfKAkbHrJ7xZMKO3dlBiab5IqUXjgKvqpjxYdI8zdXiJqYCpv92Jrki0jY5taE```.
There are two options - a Server Evaluated API Key and a Client Evaluated API Key. More on this [here](https://docs.featurehub.io/#_client_and_server_api_keys)

Client Side evaluation is intended for use in secure environments (such as microservices) and is intended for rapid client side evaluation, per request for example.

Server Side evaluation is more suitable when you are using an _insecure client_. (e.g. command line tool). This also means you evaluate one user per client.

#### 2. Create FeatureHub config:

Create `FeatureHubConfig`. You need to provide the API Key and the URL of the FeatureHub Edge server.

```ruby
config = FeatureHub::Sdk::FeatureHubConfig.new(ENV.fetch("FEATUREHUB_EDGE_URL"),
                                                 [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")])
config.init

```
    
Note, you only ever need to do this once, a Config consists of a Repository
(which holds state) and an Edge Server (which gets the updates and passes them
on to the Repository). You can have many of them if you wish, but you don't need
to. 
     
to in Rails, you might create an initializer that does this:

```ruby
Rails.configuration.fh_client = FeatureHub::Sdk::FeatureHubConfig.new(ENV.fetch("FEATUREHUB_EDGE_URL"),
                                                 [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")]).init
```

in Sinatra (our example), it might do this:

```ruby
class App < Sinatra::Base
    configure do
        set :fh_config, FeatureHub::Sdk::FeatureHubConfig.new(ENV.fetch("FEATUREHUB_EDGE_URL"),
                                                              [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")])
    end
end
```


By default, this SDK will use SSE client. If you decide to use FeatureHub polling client, after initialising the config, you can add this:

```ruby
config.use_polling_edge_service(30)
# OR
config.use_polling_edge_service # uses environment variable FEATUREHUB_POLL_INTERVAL or default of 30 
```

in this case it is configured for requesting an update every 30 seconds.

#### 3. Check FeatureHub Repository readiness and request feature state

Check for FeatureHub Repository readiness:
```ruby
if config.repository.ready?
  # do something
end
```

If you are not intending to use rollout strategies, you can pass empty context to the SDK:

```ruby
def name_arg(name)
    if config.new_context.build.feature("FEATURE_TITLE_TO_UPPERCASE").flag
        "HELLO WORLD"
    else
        "hello world"
    end
end
```


If you are using rollout strategies and targeting rules they are all determined by the active _user context_. In this example we pass `user_key` to the context :

```ruby
def name_arg(name)
    if config.new_context.user_key(name).build.feature("FEATURE_TITLE_TO_UPPERCASE").flag
        "HELLO WORLD"
    else
        "hello world"
    end
end
```

See more options to request feature states [here](https://github.com/featurehub-io/featurehub-ruby-sdk/blob/main/featurehub-sdk/lib/feature_hub/sdk/context.rb)

### Using inside popular web servers

Because most of the popular webservers use a process per request distributed request distribution model, they
will generally fork the process when they need more processes to handle the incoming traffic, and this will naturally
kill the connection to FeatureHub. It does not however reset the cached repository. To ensure your fork is back
up in running, for various frameworks you will need to ensure the Edge connection is restarted. This consists of

```ruby
config.force_new_edge_service
```

#### Resetting in Passenger 

In your `config.ru` 

```ruby
if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    if forked
      # e.g.
      # App.settings.fh_config.force_new_edge_service
    end
  end
end

```

#### Resetting in Puma

```ruby
on_worker_boot do
      # e.g.
      # App.settings.fh_config.force_new_edge_service
end

```

#### Resetting in Unicorn

```ruby
after_fork do |_server, _worker|
      # e.g.
      # App.settings.fh_config.force_new_edge_service
end

```

#### Resetting in Spring 

```ruby
Spring.after_fork do 
      # e.g.
      # App.settings.fh_config.force_new_edge_service
end

```
        

### Extracting the state 

You can extract the state from a repository and store it somewhere and reload
it, but it should be done so using the JSON mechanism so it parses correctly. 

```ruby
require 'json'

state = config.repository.extract_feature_state

# somehow save it
save(state.to_json)

# some later stage, reload it or use it as a cache
config.repository.notify(:features, JSON.parse(read_state))
```

### Readyness

It is encourage that you include the ready state of the repository in your
readyness check. If your server cannot connect to your FeatureHub repository
and cannot sensibly operate without it, it is not ready. Once it has received
initial state it will remain ready even when it temporarily loses connections.

It is only if the key is invalid, or if the repository has never received state,
that the repository is marked not ready. To determine readyness: 

```ruby
config.repository.ready?
```

