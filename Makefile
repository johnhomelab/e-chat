# Variables
APP_NAME := chatwoot
RAILS_ENV ?= development
STACKLAB_ENABLED ?= true

# Targets
setup:
	gem install bundler
	bundle install
	pnpm install

db_create:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:create

db_migrate:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:migrate

db_seed:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:seed

db_reset:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:reset

db:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails db:chatwoot_prepare

console:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails console

server:
	RAILS_ENV=$(RAILS_ENV) bundle exec rails server -b 0.0.0.0 -p 3000

burn:
	bundle && pnpm install

run:
	@if [ -f ./.overmind.sock ]; then \
		echo "Overmind is already running. Use 'make force_run' to start a new instance."; \
	else \
		overmind start -f Procfile.dev; \
	fi

force_run:
	rm -f ./.overmind.sock
	rm -f tmp/pids/*.pid
	overmind start -f Procfile.dev

force_run_tunnel:
	lsof -ti:3000 | xargs kill -9 2>/dev/null || true
	rm -f ./.overmind.sock
	rm -f tmp/pids/*.pid
	overmind start -f Procfile.tunnel

debug:
	overmind connect backend

debug_worker:
	overmind connect worker

tag:
	@if [ -z "$(TAG_NAME)" ]; then \
	  read -p "Digite o nome da tag do GitHub: " TAG_NAME; \
	fi; \
	git tag $$TAG_NAME; \
	git push origin $$TAG_NAME

docker:
	@if [ -z "$(IMAGE_TAG)" ]; then \
	  read -p "Digite a tag da imagem Docker: " IMAGE_TAG; \
	fi; \
	{ docker buildx build -t stacklabdigital/kanban:$$IMAGE_TAG --build-arg STACKLAB_ENABLED=$(STACKLAB_ENABLED) --push -f ./docker/Dockerfile .; } && \
	curl -X POST http://info.stacklab.digital/webhooks/kanban \
	  -H "Content-Type: application/json" \
	  -d '{"version": "'$$IMAGE_TAG'"}' && \
	./scripts/generate_changelog_json.sh $$IMAGE_TAG stacklabdigital/kanban:$$IMAGE_TAG > /tmp/changelog.json && \
	curl -X POST http://info.stacklab.digital/webhooks/changelog \
	  -H "Content-Type: application/json" \
	  -d @/tmp/changelog.json

# Build sem stacklab (Community Edition)
docker-ce:
	$(MAKE) docker STACKLAB_ENABLED=false

# Teste apenas do changelog
changelog-test:
	@echo "Testando geração do changelog JSON:"
	@./scripts/generate_changelog_json.sh

.PHONY: setup db_create db_migrate db_seed db_reset db console server burn docker docker-ce run force_run debug debug_worker changelog-test
