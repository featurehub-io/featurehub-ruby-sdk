# Official FeatureHub Ruby SDK

## Overview

To control the feature flags from the FeatureHub Admin console, either use our [demo](https://demo.featurehub.io) version for evaluation or install the app using our guide [here](https://docs.featurehub.io/featurehub/latest/installation.html).

## SDK installation

Add the featurehub-sdk gem to your Gemfile:

```ruby
gem 'featurehub-sdk'
```

To use it in your code:

```ruby
require 'featurehub-sdk'
```

## Options to get feature updates

There are 2 ways to request feature updates via this SDK:

- **SSE (Server Sent Events) realtime updates**

  Makes a persistent connection to the FeatureHub Edge server. Any updates to features come through in near-realtime, automatically updating the repository. Recommended for long-running server applications.

- **Polling client (GET request)**

  Requests updates at a configurable interval (0 = once only). Useful for short-lived processes such as CLI tools or batch jobs.

Both options use `concurrent-ruby` to keep the connection open and update state in the background.

## Quick start

### 1. Copy your API Key

Find and copy your API Key from the FeatureHub Admin Console on the API Keys page. It will look similar to:

```
default/71ed3c04-122b-4312-9ea8-06b2b8d6ceac/fsTmCrcZZoGyl56kPHxfKAkbHrJ7xZMKO3dlBiab5IqUXjgKvqpjxYdI8zdXiJqYCpv92Jrki0jY5taE
```

There are two key types — Server Evaluated and Client Evaluated. More detail [here](https://docs.featurehub.io/#_client_and_server_api_keys).

- **Client Evaluated** keys (contain `*`) send full rollout strategy data to the SDK and evaluate strategies locally, per request. Intended for secure server-side environments such as microservices.
- **Server Evaluated** keys evaluate on the server side. Suitable for insecure clients or environments where you evaluate one user per connection.

### 2. Create FeatureHub config

```ruby
config = FeatureHub::Sdk::FeatureHubConfig.new(
  ENV.fetch("FEATUREHUB_EDGE_URL"),
  [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")]
)
config.init
```

You only ever need to do this once. A `FeatureHubConfig` holds a `FeatureHubRepository` (state) and an edge service (updates). In Rails, create an initializer:

```ruby
Rails.configuration.fh_client = FeatureHub::Sdk::FeatureHubConfig.new(
  ENV.fetch("FEATUREHUB_EDGE_URL"),
  [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")]
).init
```

In Sinatra:

```ruby
class App < Sinatra::Base
  configure do
    set :fh_config, FeatureHub::Sdk::FeatureHubConfig.new(
      ENV.fetch("FEATUREHUB_EDGE_URL"),
      [ENV.fetch("FEATUREHUB_CLIENT_API_KEY")]
    )
  end
end
```

To use the polling client instead of SSE:

```ruby
config.use_polling_edge_service(30)
# OR — reads FEATUREHUB_POLL_INTERVAL env var, defaults to 30 seconds
config.use_polling_edge_service
```

### 3. Check readiness and request feature state

```ruby
if config.repository.ready?
  # safe to evaluate features
end
```

See [Readiness](#readiness) below for details on incorporating this into health checks.

## Evaluating features

### Without a context (no rollout strategies)

```ruby
if config.new_context.build.feature("FEATURE_TITLE_TO_UPPERCASE").flag
  "HELLO WORLD"
else
  "hello world"
end
```

### With a context (rollout strategies)

Build a context with the attributes you want to use for strategy evaluation, then call `build` to push them to the server (server-evaluated keys) or trigger a poll (client-evaluated keys):

```ruby
ctx = config.new_context
             .user_key(current_user.id)
             .country("australia")
             .platform("ios")
             .version("2.3.1")
             .attribute_value("plan", "premium")
             .build

if ctx.feature("FEATURE_TITLE_TO_UPPERCASE").flag
  # ...
end
```

#### Well-known context attributes

| Method | ContextKey |
|---|---|
| `user_key(value)` | `:userkey` |
| `session_key(value)` | `:session` |
| `country(value)` | `:country` |
| `platform(value)` | `:platform` |
| `device(value)` | `:device` |
| `version(value)` | `:version` |

#### Custom attributes

```ruby
ctx.attribute_value("contract_ids", [2, 17, 45])
```

#### `assign` — bulk-set attributes from a hash

`assign` accepts a hash, maps well-known keys to their dedicated setters, and merges anything else as a custom attribute:

```ruby
ctx.assign(
  userkey: current_user.id,
  country: "nz",
  plan: "enterprise"
)
```

String keys are also accepted (`"userkey"` and `:userkey` are equivalent).

#### Construct a context with initial attributes

Pass a hash directly to `new_context` via the repository, or pre-populate at construction time:

```ruby
ctx = FeatureHub::Sdk::ClientContext.new(repository, { userkey: "u1", country: "nz" })
```

#### One-off feature evaluation with inline attributes

If you only need to check one feature and do not want to build a context, you can pass attributes directly to `feature`:

```ruby
# On the config (delegates to the repository)
config.feature("SUBMIT_COLOR_BUTTON", { country: "nz" }).string

# Or directly on the repository
config.repository.feature("SUBMIT_COLOR_BUTTON", { country: "nz", userkey: "u1" }).string
```

This creates a temporary `ClientContext` internally and evaluates the feature through it.

#### Feature value accessors

| Method | Returns |
|---|---|
| `.flag` / `.boolean` | `bool?` |
| `.string` | `String?` |
| `.number` | `Float?` |
| `.raw_json` | `String?` (raw JSON string) |
| `.json` | `Hash?` (parsed JSON) |
| `.enabled?` | `bool` (true if flag is on) |
| `.set?` | `bool` (true if a value has been set) |
| `.exists?` | `bool` (true if the feature exists in the repository) |

## Feature interceptors

Interceptors let you override feature values at runtime without changing the repository. They are evaluated before rollout strategies.

### Environment variable interceptor

Override any feature at runtime using environment variables:

```
FEATUREHUB_OVERRIDE_FEATURES=true
FEATUREHUB_MY_FEATURE=true
FEATUREHUB_SUBMIT_COLOR_BUTTON=green
```

```ruby
config.repository.register_interceptor(FeatureHub::Sdk::EnvironmentInterceptor.new)
```

### Local YAML interceptor

Override features from a YAML file. Useful during development or testing:

```yaml
# featurehub-overrides.yaml
flagValues:
  MY_FEATURE: true
  SUBMIT_COLOR_BUTTON: green
  MAX_RETRIES: 3
```

```ruby
config.repository.register_interceptor(
  FeatureHub::Sdk::LocalYamlValueInterceptor.new
  # OR specify a file explicitly:
  # FeatureHub::Sdk::LocalYamlValueInterceptor.new("path/to/overrides.yaml")
)
```

The file path defaults to `featurehub-overrides.yaml` in the current directory, or can be set via `FEATUREHUB_LOCAL_YAML`. Pass `watch: true` to automatically reload the file on changes:

```ruby
FeatureHub::Sdk::LocalYamlValueInterceptor.new(watch: true, watch_interval: 5)
```

## Offline / local-only mode with LocalYamlStorage

`LocalYamlStorage` loads features from a YAML file directly into the repository, with no Edge connection required. It uses the same file format as `LocalYamlValueInterceptor`. This is useful for tests, CI environments, or services that manage their own feature state.

```yaml
# features.yaml
flagValues:
  MY_FLAG: true
  SUBMIT_COLOR_BUTTON: green
  MAX_RETRIES: 3
  PRICING_CONFIG:
    base: 9.99
    tiers: [19.99, 49.99]
```

```ruby
repository = FeatureHub::Sdk::FeatureHubRepository.new
store = FeatureHub::Sdk::LocalYamlStorage.new(repository)
# OR specify a file:
store = FeatureHub::Sdk::LocalYamlStorage.new(repository, filename: "features.yaml")
# OR via env var FEATUREHUB_LOCAL_YAML

repository.feature("MY_FLAG").flag  # => true
```

The file path defaults to `featurehub-overrides.yaml` or the `FEATUREHUB_LOCAL_YAML` environment variable. Complex values (hashes, arrays) are serialised to a JSON string and stored as a `JSON` feature type.

## Caching feature state in Redis

`RedisSessionStore` persists feature values from a `FeatureHubRepository` to Redis. On startup it replays cached features into the repository, then listens for live updates and writes newer versions back. A background timer re-reads all features periodically so updates from other processes are picked up automatically.

> **Warning:** Do not use `RedisSessionStore` with server-evaluated features. Each server-evaluated context resolves to different values; sharing a single Redis key across processes will cause them to overwrite each other's state.

```ruby
# Requires the 'redis' gem: gem 'redis', '~> 5'
store = FeatureHub::Sdk::RedisSessionStore.new(
  "redis://localhost:6379",
  config.repository,
  {
    prefix:    "myapp",       # Redis key prefix (default: "featurehub")
    namespace: 0,             # Redis DB index (default: 0)
    timeout:   60,            # Seconds between periodic reloads (default: 30)
    password:  "secret"       # Optional Redis password
  }
)

# Register it so it also receives live updates
config.register_raw_update_listener(store)

# Shut down cleanly
store.close
```

Redis keys used:
- `{prefix}_ids` — a Redis SET of feature IDs
- `{prefix}_{id}` — the JSON-encoded feature state for each feature

## Custom raw update listeners

`RawUpdateFeatureListener` is a base class you can subclass to observe every raw feature update that flows through the repository, regardless of source. Register an instance with the repository (or config) and override only the callbacks you need:

```ruby
class MyAuditListener < FeatureHub::Sdk::RawUpdateFeatureListener
  def process_updates(features, source)
    features.each { |f| Rails.logger.info("bulk update from #{source}: #{f["key"]}") }
  end

  def process_update(feature, source)
    Rails.logger.info("single update from #{source}: #{feature["key"]}")
  end

  def delete_feature(feature, source)
    Rails.logger.warn("deleted from #{source}: #{feature["key"]}")
  end
end

config.register_raw_update_listener(MyAuditListener.new)
```

Callbacks are dispatched asynchronously via `Concurrent::Future`. The `source` parameter will be `"streaming"`, `"polling"`, `"local-yaml"`, `"redis-store"`, or `"unknown"`.

All listeners are closed automatically when `config.close` or `repository.close` is called.

## Using inside popular web servers

Most popular web servers fork processes to handle traffic. Forking kills the Edge connection but preserves the cached repository. Call `force_new_edge_service` in your framework's post-fork hook to restart the connection:

```ruby
config.force_new_edge_service
```

#### Passenger

In `config.ru`:

```ruby
if defined?(PhusionPassenger)
  PhusionPassenger.on_event(:starting_worker_process) do |forked|
    App.settings.fh_config.force_new_edge_service if forked
  end
end
```

#### Puma

```ruby
on_worker_boot do
  App.settings.fh_config.force_new_edge_service
end
```

#### Unicorn

```ruby
after_fork do |_server, _worker|
  App.settings.fh_config.force_new_edge_service
end
```

#### Spring

```ruby
Spring.after_fork do
  App.settings.fh_config.force_new_edge_service
end
```

## Extracting and restoring state

You can snapshot the repository state and reload it later (e.g. as a warm-start cache):

```ruby
require 'json'

# Snapshot
state = config.repository.extract_feature_state
save(state.to_json)

# Restore
config.repository.notify(:features, JSON.parse(read_state))
```

## Readiness

It is recommended to include the repository's ready state in your health/readiness check. The repository becomes ready once it has received its first successful update, and stays ready even through temporary connection loss. It is only not ready if the API key is invalid or no state has ever been received:

```ruby
config.repository.ready?
```

## Examples

Check our example Sinatra app [here](https://github.com/featurehub-io/featurehub-ruby-sdk/tree/main/example/sinatra).
