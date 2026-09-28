#!/usr/bin/env bash
# Opens Session Manager port forwarding from 127.0.0.1 to the private EKS API endpoint through
# the relay instance, and points the cluster's kubeconfig entry at it. The API endpoint is
# private in every environment (ADR 0007): nothing listens on a public address, and the relay
# has no public IP and no inbound rules.
#
# Usage: scripts/api-tunnel.sh REGION CLUSTER RELAY_INSTANCE_ID ENDPOINT_URL [LOCAL_PORT]
# The environment root prints the full command as the `api_tunnel_command` output. Keep this
# running, then in another terminal use kubectl, or apply Terraform with
# -var=kubernetes_api_url=https://127.0.0.1:LOCAL_PORT. Uses the AWS_PROFILE in the environment;
# needs the AWS CLI v2 with the Session Manager plugin, and kubectl.
set -euo pipefail

if [ "$#" -lt 4 ]; then
  sed -n '7,11p' "$0" >&2
  exit 2
fi

region="$1"
cluster="$2"
relay="$3"
endpoint_host="${4#https://}"
port="${5:-8443}"

aws eks update-kubeconfig --name "$cluster" --region "$region" > /dev/null
cluster_arn="$(kubectl config view --minify -o jsonpath='{.clusters[0].name}')"
# Same certificate, reached through the tunnel: kubectl verifies it against the real host name.
kubectl config set-cluster "$cluster_arn" --server="https://127.0.0.1:$port" \
  --tls-server-name="$endpoint_host" > /dev/null

echo "kubeconfig entry $cluster_arn now uses https://127.0.0.1:$port; forwarding until Ctrl-C."
exec aws ssm start-session --region "$region" --target "$relay" \
  --document-name AWS-StartPortForwardingSessionToRemoteHost \
  --parameters "{\"host\":[\"$endpoint_host\"],\"portNumber\":[\"443\"],\"localPortNumber\":[\"$port\"]}"
