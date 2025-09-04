# ====== Config de base ======
SHELL := /bin/bash
.DEFAULT_GOAL := help

# Groupes
GROUP_media     := media
GROUP_domotics  := domotics
GROUP_core      := traefik watchtower portainer nginx

# Parsing args
ARGS := $(wordlist 2,$(words $(MAKECMDGOALS)),$(MAKECMDGOALS))
expand_group = $(if $(GROUP_$(1)),$(GROUP_$(1)),$(1))
SERVICES := $(foreach a,$(ARGS),$(call expand_group,$(a)))

define ensure_services
	@if [ -z "$(SERVICES)" ]; then \
	  echo "❌ Aucun service fourni."; \
	  echo "   Exemples : make up media | make down domotics | make restart portainer"; \
	  exit 1; \
	fi
endef

# Découverte dynamique (tous dossiers avec docker-compose.yml)
ALL_SERVICES := $(shell bash -lc 'for d in */; do [[ -f "$$d/docker-compose.yml" ]] && echo $${d%/}; done')

# Helper : n'exécute que si le dossier a un compose
define do_if_exists
  if [ -f "$(1)/docker-compose.yml" ]; then \
    echo "$(2) $(1)"; \
    docker compose -f $(1)/docker-compose.yml $(3); \
  else \
    echo "ℹ️  skip $(1) (pas de docker-compose.yml)"; \
  fi
endef

# ====== Cibles usuelles ======
.PHONY: help up down restart logs ps pull rebuild status all-up all-down all-restart all-status health health-media health-domotics

help:
	@echo "🧰 Make targets:"
	@echo "  make up <svc|groupe>        - docker compose up -d"
	@echo "  make down <svc|groupe>      - docker compose down"
	@echo "  make restart <svc|groupe>   - down puis up -d"
	@echo "  make logs <svc|groupe>      - logs -f"
	@echo "  make ps <svc|groupe>        - docker compose ps"
	@echo "  make pull <svc|groupe>      - pull des images"
	@echo "  make rebuild <svc|groupe>   - up -d --build"
	@echo "  make status [svc|groupe]    - état conteneurs (filtré ou global)"
	@echo "  make all-up|all-down|all-restart|all-status"
	@echo "  make health [svc|groupe]    - checks HTTP rapides"
	@echo "  make health-media           - checks de ta stack media"
	@echo "  make health-domotics        - check Home Assistant (8123)"

up:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  $(call do_if_exists,$$svc,🚀 Up,up -d); \
	done

down:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  $(call do_if_exists,$$svc,🛑 Down,down); \
	done

restart:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  if [ -f "$$svc/docker-compose.yml" ]; then \
	    echo "�� Restart $$svc"; \
	    docker compose -f $$svc/docker-compose.yml down && \
	    docker compose -f $$svc/docker-compose.yml up -d; \
	  else \
	    echo "ℹ️  skip $$svc (pas de docker-compose.yml)"; \
	  fi \
	done

logs:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  $(call do_if_exists,$$svc,📜 Logs,logs -f); \
	done

ps:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  $(call do_if_exists,$$svc,📋 PS,ps); \
	done

pull:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  $(call do_if_exists,$$svc,⬇️  Pull,pull); \
	done

rebuild:
	$(call ensure_services)
	@for svc in $(SERVICES); do \
	  $(call do_if_exists,$$svc,🏗️  Rebuild,up -d --build); \
	done

status:
	@if [ -n "$(SERVICES)" ]; then \
	  echo "🔎 Status (filtré) : $(SERVICES)"; \
	  docker ps --format 'table {{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' \
	    | grep -E '(^NAMES|$(shell echo $(SERVICES) | sed "s/ /|/g"))' \
	    | column -t -s '|' ; \
	else \
	  echo "🔎 Status (tous conteneurs)"; \
	  docker ps --format 'table {{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' \
	    | column -t -s '|' ; \
	fi

# ====== Cibles globales (dynamiques) ======
all-up:
	@echo "🚀 Up (auto) : $(ALL_SERVICES)"
	@for svc in $(ALL_SERVICES); do \
	  docker compose -f $$svc/docker-compose.yml up -d; \
	done

all-down:
	@echo "🛑 Down (auto) : $(ALL_SERVICES)"
	@for svc in $(ALL_SERVICES); do \
	  docker compose -f $$svc/docker-compose.yml down; \
	done

all-restart:
	@echo "🔁 Restart (auto) : $(ALL_SERVICES)"
	@for svc in $(ALL_SERVICES); do \
	  docker compose -f $$svc/docker-compose.yml down && \
	  docker compose -f $$svc/docker-compose.yml up -d; \
	done

all-status:
	@echo "🔎 Status global"
	@docker ps --format 'table {{.Names}}|{{.Image}}|{{.Status}}|{{.Ports}}' | column -t -s '|'

# ====== Health checks ======
# Utilise curl pour vérifier les UIs usuelles
define _curl_check
	code=$$(curl -s -o /dev/null -m 3 -w '%{http_code}' "$(1)"); \
	if [[ $$code =~ ^2|3 ]]; then echo "✅ $(2) ($(1)) [$$code]"; else echo "❌ $(2) ($(1)) [$$code]"; fi
endef

health:
	@if [ -n "$(SERVICES)" ]; then \
	  echo "🩺 Health (filtré) : $(SERVICES)"; \
	  for s in $(SERVICES); do \
	    case $$s in \
	      media)        make -s health-media ;; \
	      domotics)     make -s health-domotics ;; \
	      *)            echo "ℹ️  Pas de checks définis pour '$$s'";; \
	    esac; \
	  done; \
	else \
	  echo "🩺 Health (global)"; \
	  make -s health-media || true; \
	  make -s health-domotics || true; \
	fi

# Checks stack media (ports host)
health-media:
	@echo "🩺 media"
	@$(call _curl_check,http://localhost:8080,qBittorrent (via Gluetun))
	@$(call _curl_check,http://localhost:9117,Jackett)
	@$(call _curl_check,http://localhost:7878,Radarr)
	@$(call _curl_check,http://localhost:8989,Sonarr)
	@$(call _curl_check,http://localhost:5055,Jellyseerr)
	@$(call _curl_check,http://localhost:8191/health,FlareSolverr /health)

# Checks stack domotics
health-domotics:
	@echo "🩺 domotics"
	@$(call _curl_check,http://localhost:8123,Home Assistant)

# Évite que make tente d'exécuter les noms de services comme cibles
%:
	@:
