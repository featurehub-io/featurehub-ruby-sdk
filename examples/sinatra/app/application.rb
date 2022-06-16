# frozen_string_literal: true

require "rack"
require 'sinatra'
require "featurehub-sdk"
require "json"

def configure_featurehub
  config = FeatureHub::Sdk::FeatureHubConfig.new(ENV.fetch("FEATUREHUB_EDGE_URL", "https://zjbisc.demo.featurehub.io"),
                                                 [
                                                   ENV.fetch("FEATUREHUB_CLIENT_API_KEY",
                                                             "default/9b71f803-da79-4c04-8081-e5c0176dda87/CtVlmUHirgPd9Qz92Y0IQauUMUv3Wb*4dacoo47oYp6hSFFjVkG")
                                                 ])
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

    set :fh_config, configure_featurehub
    set :users, {}
  end

  # Routes
  # "resolve" a specific todo for this user
  put("/todo/:user/:id/resolve") do
    user = params['user']
    id = params['id'].to_s
    todos = user_todos(user)
    todo = todos.detect { |todo| todo.id.to_s == id }
    todo&.resolved = true
    todo_list(user)
  end

  # delete a specific todo for this user
  delete('/todo/:user/:id') do
    user = params['user']
    id = params['id'].to_s
    todos = user_todos(user)
    new_todos = todos.filter { |todo| todo.id.to_s != id }
    settings.users[user] = new_todos
    todo_list(user)
  end

  # delete a user
  delete('/todo/:user') do
    user = params['user']
    delete settings.users[user]
    status(204)
  end

  # add a user and the todo in the body
  post('/todo/:user') do
    user = params['user']
    todos = user_todos(user)
    new_todo = JSON.parse(request.body.read)
    if new_todo["title"].nil?
      status(400)
    else
      todos.push(Todo.new(new_todo["id"] || 1, new_todo["title"], new_todo["resolved"] || false))
      todo_list(user)
    end
  end

  # get all the todos for this user
  get('/todo/:user') do
    todo_list(params["user"])
  end

  get( "/health/readiness") do
    if config.repository.ready?
      "ok"
    else
      status(500)
    end
  end

  private

  def todo_list(user)
    ctx = settings.fh_config.new_context.user_key(user).build
    todos = user_todos(user)

    new_todos = []

    todos.each do |todo|
      new_todos.push(Todo.new(todo.id, process_title(ctx, todo.title), todo.resolved).to_h)
    end

    new_todos.to_json
  end

  def user_todos(user)
    todos = settings.users[user] || []
    settings.users[user] = todos
  end

  def process_title(ctx, title)
    new_title = title

    if ctx.set?("FEATURE_STRING") && title == "buy"
      new_title = "#{title} #{ctx.string('FEATURE_STRING')}"
    end

    if ctx.set?("FEATURE_NUMBER") && title == "pay"
      new_title = "#{title} #{ctx.number('FEATURE_NUMBER')}"
    end

    if ctx.set?("FEATURE_JSON") && title == "find"
      new_title = "#{title} #{ctx.json('foo')}"
    end

    if ctx.enabled?("FEATURE_TITLE_TO_UPPERCASE")
      new_title = new_title.upcase
    end

    puts("features via repository: #{settings.fh_config.repository.features}")
    puts("features via edge service: #{settings.fh_config.get_or_create_edge_service.repository}")

    puts("enabled? #{ctx.repo.features}")
    puts(ctx.enabled?("FEATURE_TITLE_TO_UPPERCASE"))
    puts(ctx.flag("FEATURE_TITLE_TO_UPPERCASE"))
    puts(settings.fh_config.repository.feature("FEATURE_TITLE_TO_UPPERCASE").feature_type)
    puts(settings.fh_config.repository.feature("FEATURE_TITLE_TO_UPPERCASE").flag)

    new_title
  end
end
