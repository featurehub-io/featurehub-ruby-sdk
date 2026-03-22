# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
bundle install          # Install dependencies
bundle exec rake        # Run tests + linting (default)
bundle exec rspec       # Run tests only
bundle exec rubocop     # Lint only

# Run a single test file
bundle exec rspec spec/feature_hub/sdk/feature_hub_config_spec.rb

# Run a specific test by line number
bundle exec rspec spec/feature_hub/sdk/feature_hub_config_spec.rb:42
```

## Architecture

This is the FeatureHub Ruby SDK (gem: `featurehub-sdk`, version 1.3.0), targeting Ruby >= 3.2. All code lives under `lib/feature_hub/sdk/` and is namespaced as `FeatureHub::Sdk`.

### Core Data Flow

```
FeatureHubConfig.init(url, api_key)
  → creates EdgeService (streaming SSE or polling HTTP)
  → edge service receives feature JSON from FeatureHub server
  → FeatureHubRepository stores feature states

config.new_context().user_key("id").build()
  → ClientEvalContext: polls edge, evaluates strategies locally
  → ServerEvalContext: sends context as HTTP header, server evaluates

context.feature("MY_FLAG").boolean
  → FeatureStateHolder checks interceptors, then calls repository.apply(strategies, ctx)
  → ApplyFeature matches rollout strategies, returns Applied(value)
```

### Key Classes

- **FeatureHubConfig** ([feature_hub_config.rb](lib/feature_hub/sdk/feature_hub_config.rb)): Entry point. Detects client vs server evaluation by checking for `*` in the API key. Manages edge service lifecycle. Call `new_context()` to get a context builder.

- **FeatureHubRepository** ([feature_repository.rb](lib/feature_hub/sdk/feature_repository.rb)): Stores features as a hash (symbol keys → `FeatureStateHolder`). Notifies listeners on changes (`:features`, `:feature`, `:delete_feature`, `:failed`). Checks interceptors before applying strategies. Tracks readiness via `@ready`.

- **FeatureStateHolder** ([feature_state_holder.rb](lib/feature_hub/sdk/feature_state_holder.rb)): Wraps feature JSON (`key`, `id`, `type`, `value`, `version`, `l` (locked), `strategies`). Provides typed accessors: `.flag`, `.string`, `.number`, `.raw_json`, `.boolean`. Supports `with_context(ctx)` for strategy evaluation.

- **Context classes** ([context.rb](lib/feature_hub/sdk/context.rb)): Fluent builder pattern — `context.user_key("x").platform("ios").country("gb").build()`. Attributes stored as `symbol → [array]`. Two subclasses: `ClientEvalFeatureContext` (local strategy eval) and `ServerEvalFeatureContext` (server-side eval, sends `x-featurehub` header).

- **Edge services**: `StreamingEdgeService` ([streaming_edge_service.rb](lib/feature_hub/sdk/streaming_edge_service.rb)) uses SSE via `ld-eventsource`. `PollingEdgeService` ([poll_edge_service.rb](lib/feature_hub/sdk/poll_edge_service.rb)) uses Faraday with `Concurrent::TimerTask`, supports ETags. Call `force_new_edge_service()` after process fork (Puma/Passenger/Unicorn).

- **ApplyFeature** ([impl/apply_features.rb](lib/feature_hub/sdk/impl/apply_features.rb)): Client-side strategy evaluator. Iterates rollout strategies, calculates percentage allocation via Murmur3 hash of `percentage_key + feature_id`, matches attribute conditions via `MatcherRegistry`. Returns `Applied(matched:, value:)`.

- **EnvironmentInterceptor** ([interceptors.rb](lib/feature_hub/sdk/interceptors.rb)): Override features at runtime via `FEATUREHUB_OVERRIDE_FEATURES=true` + `FEATUREHUB_<FEATURE_NAME>=<value>` env vars.

### Client vs Server Evaluation

- **Client-evaluated** API key contains `*` (e.g., `abc*def`): full strategy data sent to SDK, evaluated locally by `ApplyFeature`.
- **Server-evaluated** API key has no `*`: context attributes sent as `x-featurehub` HTTP header, server evaluates and returns resolved values.

### Strategy Attribute Matchers

`MatcherRegistry` dispatches to typed matchers based on `field_type`: `BOOLEAN`, `STRING`/`DATE`/`DATE_TIME` (via `StringMatcher`), `NUMBER`, `SEMANTIC_VERSION` (uses `sem_version` gem), `IP_ADDRESS` (CIDR support). All conditions in a strategy must match for the strategy to apply.

## RBS Type Signatures

Type definitions live in [sig/feature_hub/featurehub.rbs](sig/feature_hub/featurehub.rbs). Key signatures to be aware of:

- **Feature value type**: `[bool? | String? | Float?]` — the union type used throughout for feature values (`Applied#value`, `FeatureStateHolder#value`, `RolloutStrategy#value`, `InterceptorValue`)
- **`FeatureStateHolder#initialize`** takes `key:`, `repo:`, `feature_state:`, `parent_state:`, and `ctx:` — the `parent_state` and `ctx` support the `with_context` pattern for context-scoped evaluation
- **`InternalFeatureRepository`** is the abstract interface that `FeatureHubRepository` implements; `FeatureStateHolder` and context classes depend on this interface, not the concrete class
- **`ClientContext#build`** returns `ClientContext` (async); **`build_sync`** also returns `ClientContext` (blocking)
- **`FeatureHubConfig#repository`** takes an optional `InternalFeatureRepository?` and returns one — it acts as both getter and setter
- **`RolloutStrategyAttribute`**: `values` is `Array[[bool? | String? | Float?]]`; use `float_values` / `str_values` for typed access
- **`RolloutStrategyCondition`**: predicate methods only (e.g., `equals?`, `regex?`, `includes?`) — no raw string comparison against condition type strings

## Conventions

- `# frozen_string_literal: true` on every file
- Double-quoted strings (RuboCop enforced)
- Feature keys stored/looked up as symbols internally
- RuboCop: max line length 120, metrics cops disabled, documentation disabled
- Tests mirror lib structure: `spec/feature_hub/sdk/**/*_spec.rb`
- Use `instance_double` for mocking, `aggregate_failures` for multiple assertions
