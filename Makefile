e2e:
	docker build -t todo-server:e2e --progress=plain -f examples/sinatra/Dockerfile .

run-e2e: e2e

cop:
	bundle exec rubocop -a

spec:
	bundle exec rspec

ci: cop spec