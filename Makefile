# Every target except test-live runs offline: no AWS account, no credentials, no cluster.
# Terraform providers, Helm charts' schemas and scanner rules are downloaded on first use.
# CI runs `make verify`; the shared lint, secret and security checks it also runs are listed in the README.

SHELL := bash
.SHELLFLAGS := -euo pipefail -c

TF_DIR      := infra/terraform
TF_MODULES  := $(sort $(dir $(wildcard $(TF_DIR)/modules/*/main.tf)))
TF_ENVS     := $(sort $(dir $(wildcard $(TF_DIR)/envs/*/main.tf)))
TF_TESTED   := $(sort $(dir $(patsubst %/tests/,%/,$(dir $(wildcard $(TF_DIR)/*/*/tests/*.tftest.hcl)))))
CHART       := charts/catalog-api
RENDERED    := build/rendered
KUBE_VERSION := 1.35.0
TOOLS       := $(CURDIR)/.tools/bin
CHECKOV     ?= uvx checkov==3.3.19
PYTEST      ?= uv run --no-project --with-requirements tests/requirements.txt python -m pytest

export TF_PLUGIN_CACHE_DIR ?= $(HOME)/.terraform.d/plugin-cache
export TF_IN_AUTOMATION := 1

KUBECONFORM := $(TOOLS)/kubeconform -strict -summary -kubernetes-version $(KUBE_VERSION) \
	-cache .cache/kubeconform -schema-location default \
	-schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json'

.PHONY: verify tools terraform tf-fmt tf-validate tf-lint tf-test helm render kubeconform \
	render-test checkov trivy test-live clean help

## verify: every offline check, in the order CI runs them
verify: terraform helm kubeconform render-test checkov trivy
	@echo "verify: all checks passed"

## tools: install the pinned kubeconform into .tools/bin
tools:
	@scripts/install-tools.sh $(TOOLS)

## terraform: fmt, validate, tflint and mocked terraform test
terraform: tf-fmt tf-validate tf-lint tf-test

tf-fmt:
	terraform fmt -check -recursive $(TF_DIR)

tf-validate:
	@mkdir -p "$$TF_PLUGIN_CACHE_DIR"
	@for dir in $(TF_MODULES) $(TF_ENVS); do \
	  echo "validate $$dir"; \
	  terraform -chdir=$$dir init -backend=false -input=false > /dev/null; \
	  terraform -chdir=$$dir validate -no-color > /dev/null; \
	done

tf-lint:
	tflint --init --config "$(CURDIR)/.tflint.hcl" > /dev/null
	tflint --recursive --config "$(CURDIR)/.tflint.hcl" --chdir $(TF_DIR)

tf-test: tf-validate
	@for dir in $(TF_TESTED); do \
	  echo "terraform test $$dir"; \
	  terraform -chdir=$$dir test -no-color; \
	done

## helm: lint the chart with defaults, each ci/ file and each environment's values
helm:
	helm lint $(CHART) --strict
	@for values in $(CHART)/ci/*.yaml gitops/environments/*/values/catalog-api.yaml; do \
	  echo "helm lint --values $$values"; \
	  helm lint $(CHART) --strict --values $$values --quiet; \
	done

## render: helm template and kustomize build everything into build/rendered
render:
	@scripts/render.sh $(RENDERED)

## kubeconform: schema-validate rendered manifests, including Argo CD and Karpenter CRDs
kubeconform: tools render
	@mkdir -p .cache/kubeconform
	$(KUBECONFORM) $(RENDERED) $(RENDERED)-hooks

## render-test: pytest assertions on rendered charts and the app-of-apps
render-test:
	$(PYTEST) -q tests

## checkov: Terraform and rendered Kubernetes manifests, no check skips (.terraform holds downloaded providers)
checkov: render
	$(CHECKOV) --quiet --compact --framework terraform --directory $(TF_DIR) --skip-path '\.terraform'
	$(CHECKOV) --quiet --compact --framework kubernetes --directory $(RENDERED)

## trivy: misconfiguration scan of Terraform, chart, manifests and test hook (HIGH, CRITICAL fail)
trivy: render
	trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL \
	  --skip-dirs '**/.terraform' --skip-dirs .cache --skip-dirs .tools .

## test-live: MANUAL. Apply dev to a real AWS account, check it, destroy it (see docs/live-test.md)
test-live:
	@scripts/test-live.sh

clean:
	rm -rf build .cache
	find $(TF_DIR) -type d -name .terraform -prune -exec rm -rf {} +

help:
	@grep -E '^## ' $(MAKEFILE_LIST) | sed 's/^## //'
