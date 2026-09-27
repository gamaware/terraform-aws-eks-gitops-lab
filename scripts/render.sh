#!/usr/bin/env bash
# Renders every manifest Argo CD would apply, offline, into build/rendered/:
#   - the storefront chart with each ci/ values file and each environment's values file;
#   - each environment's app-of-apps (Kustomize) and its Karpenter NodePool and EC2NodeClass.
# The chart's `helm test` hook goes to build/rendered-hooks/: kubeconform validates it, but the
# policy scanners skip it because it is a short-lived test pod that runs only on a live release.
set -euo pipefail

out="${1:-build/rendered}"
hooks="$out-hooks"
kube_version="1.35.0"

rm -rf "$out" "$hooks"
mkdir -p "$out" "$hooks"

for values in charts/storefront/ci/*.yaml; do
  name="$(basename "$values" .yaml)"
  helm template storefront charts/storefront --namespace storefront \
    --kube-version "$kube_version" --values "$values" --skip-tests > "$out/chart-ci-$name.yaml"
done

for env_dir in gitops/environments/*/; do
  env="$(basename "$env_dir")"
  helm template storefront charts/storefront --namespace storefront \
    --kube-version "$kube_version" --values "$env_dir/values/storefront.yaml" --skip-tests > "$out/chart-$env.yaml"
  kubectl kustomize "$env_dir" > "$out/gitops-$env.yaml"
  for manifest in "$env_dir"/karpenter/*.yaml; do
    printf -- '---\n'
    cat "$manifest"
  done > "$out/karpenter-$env.yaml"
done

cat gitops/namespaces/*.yaml > "$out/namespaces.yaml"

helm template storefront charts/storefront --namespace storefront \
  --kube-version "$kube_version" --show-only templates/tests/test-connection.yaml > "$hooks/chart-test-hook.yaml"

echo "rendered $(find "$out" -name '*.yaml' | wc -l | tr -d ' ') files into $out"
