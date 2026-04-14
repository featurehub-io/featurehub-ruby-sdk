# frozen_string_literal: true

require "rack"
require "sinatra"
require "featurehub-sdk"
require "json"

def configure_featurehub(logger)
  puts "FeatureHub SDK Version is #{FeatureHub::Sdk::VERSION}"

  config = FeatureHub::Sdk::FeatureHubConfig.new(nil, nil, nil, nil, logger)
  repo = config.repository

  if ENV["FEATUREHUB_REDIS_STORE"]
    config.register_raw_update_listener(FeatureHub::Sdk::RedisSessionStore.new(ENV["FEATUREHUB_REDIS_STORE"], repo,
                                                                               { logger: logger, timeout: 3 }))
  end

  if ENV["FEATUREHUB_MEMCACHE_STORE"]
    config.register_raw_update_listener(FeatureHub::Sdk::MemcacheSessionStore.new(ENV["FEATUREHUB_MEMCACHE_STORE"],
                                                                                  config, { logger: logger,
                                                                                            refresh_timeout: 3 }))
  end

  if ENV["FEATUREHUB_LOCAL_YAML"]
    config.register_raw_update_listener(FeatureHub::Sdk::LocalYamlStore.new(repo))
    config.register_interceptor(FeatureHub::Sdk::LocalYamlValueInterceptor.new(watch: true))
  end

  # connect to edge service
  config.init
end

Todo = Struct.new(:id, :title, :resolved)

# sample app
class App < Sinatra::Base
  # Middleware
  # use Rack::CanonicalHost, ENV['CANONICAL_HOST']
  configure do
    rack = File.new("logs/rack.log", "a+")
    use Rack::CommonLogger, rack

    logger = Logger.new($stdout)
    set :logger, logger
    set :fh_config, configure_featurehub(logger)
    set :users, {}
  end

  before do
    content_type "application/json"
  end

  # Routes
  # "resolve" a specific todo for this user
  put("/todo/:user/:id/resolve") do
    user = params["user"]
    id = params["id"].to_s
    todos = user_todos(user)
    todo = todos.detect { |todo| todo.id.to_s == id }
    todo&.resolved = true
    todo_list(user)
  end

  # delete a specific todo for this user
  delete("/todo/:user/:id") do
    user = params["user"]
    id = params["id"].to_s
    todos = user_todos(user)
    new_todos = todos.filter { |todo| todo.id.to_s != id }
    settings.users[user] = new_todos
    todo_list(user)
  end

  # delete a user
  delete("/todo/:user") do
    user = params["user"]
    users = settings.users || {}
    users[user] = []
    status(204)
  end

  # add a user and the todo in the body
  post("/todo/:user") do
    user = params["user"]
    todos = user_todos(user)
    new_todo = JSON.parse(request.body.read)
    if new_todo["title"].nil?
      status(400)
    else
      settings.logger.debug("todo is #{new_todo}")
      todos.push(Todo.new(new_todo["id"] || 1, new_todo["title"], new_todo["resolved"] || false))
      todo_list(user)
    end
  end

  # get all the todos for this user
  get("/todo/:user") do
    todo_list(params["user"])
  end

  get("/health/readiness") do
    if settings.fh_config.repository.ready?
      "ok"
    else
      status(500)
    end
  end

  get("/health/liveness") do
    if settings.fh_config.repository.ready?
      "ok"
    else
      status(500)
    end
  end

  get("/health/disconnect") do
    settings.fh_config.close_edge
    status 200
  end

  private

  def todo_list(user)
    ctx = settings.fh_config.new_context.user_key(user).build
    todos = user_todos(user)

    new_todos = []

    todos.each do |todo|
      new_todos.push(Todo.new(todo.id, process_title(ctx, todo.title), todo.resolved).to_h)
    end

    settings.logger.debug("todos #{new_todos}")
    new_todos.to_json
  end

  def user_todos(user)
    todos = settings.users[user] || []
    settings.users[user] = todos
  end

  def process_title(ctx, title)
    new_title = title

    new_title = "#{title} #{ctx.string("FEATURE_STRING")}" if ctx.set?("FEATURE_STRING") && title == "buy"

    new_title = "#{title} #{ctx.number("FEATURE_NUMBER")}" if ctx.set?("FEATURE_NUMBER") && title == "pay"

    if ctx.set?("FEATURE_JSON") && title == "find"
      json = ctx.json("FEATURE_JSON")
      new_title = if json.nil?
                    title.to_s
                  else
                    "#{title} #{json["foo"]}"
                  end
    end

    new_title = new_title.upcase if ctx.enabled?("FEATURE_TITLE_TO_UPPERCASE")

    new_title
  end
end
