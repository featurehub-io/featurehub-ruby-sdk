## [2.1.0] - 2026-04-14
        
- Once the Config is closed it won't reopen
- Added Memcache cache that operates on the same general principles as Redis.
It requires Dalli to be available in your dependencies at least 4.x.
- The requirement for faraday 2+ has been relaxed, just faraday is now required in
the gemspec. It has been tested with 2 and 1.
- Redis session store has been updated so it only uses two keys

## [2.0.1] - 2026-03-27

- Remove `FeatureHub::Sdk.default_logger`; logger now defaults to `nil` instead of a stdout DEBUG logger
- Replace all `logger.` calls with `logger&.` so a nil logger is silently ignored

## [2.0.0] - 2026-03-22

- Refactor FeatureState to FeatureStateHolder to be consistent with other SDKs
- Add FeatureValueType to reduce duplication
- Add local YAML file interceptor with an optional timer to watch for changes
- Add `RawUpdateFeatureListener` base class so custom listeners can react to raw edge updates (including update source tracking)
- Add `LocalYamlStore`: load features from a local YAML file without an Edge server, as an alternative to the value interceptor
- Add `RedisSessionStore`: persist features in Redis so they survive process restarts and are shared across processes (client-evaluated only)
- Support punch-through context evaluation for external stores so per-request context attributes are applied even when features come from Redis or YAML
- Add `value` accessor to `FeatureStateHolder` as a convenience shortcut alongside the typed accessors
- Edge services now explicitly close the repository on shutdown

## [1.3.0] - 2026-01-11

- update gem dependencies
- bump minimum ruby version to 3.2

## [1.2.3] - 2024-01-12

- fix for Interceptor contributed by Lukas

## [1.2.2] - 2023-08-07

- Changed the log levels for API logging to debug
- Widened the possible transitive dependencies

## [1.2.1] - 2022-11-21

- Minor bug fixes (Chris Spalding)

## [1.2.0] - 2022-10-14

- Fixing polling client for server eval
- Added in tests for polling client
- Added in server eval for streaming client
- Added expired environment support for polling and streaming
- Added cache busting for server eval polling client
- 

## [1.1.0] - 2022-10-12

- Adds support for array values in flag evaluation contexts via [this PR](https://github.com/featurehub-io/featurehub-ruby-sdk/pull/12)

## [1.0.0] - 2022-06-06

- Initial release, feature complete
