#!/usr/bin/env bash
# Installs the pinned kubeconform release into .tools/bin and verifies its SHA-256 checksum.
# Everything else (terraform, helm, kubectl, checkov, trivy) is listed in README prerequisites.
set -euo pipefail

version="v0.8.0"
dest="${1:-.tools/bin}"

case "$(uname -s)-$(uname -m)" in
  Darwin-arm64) asset="kubeconform-darwin-arm64.tar.gz"; sum="f84f4dfbebf4a6b0b230385fa065a39ea35e02608c2b50d025dcf64775a69d67" ;;
  Darwin-x86_64) asset="kubeconform-darwin-amd64.tar.gz"; sum="71dbc87ac9f24099a62b93570e65aa06312ba6ac8aea63b7f86e9d999edf5a92" ;;
  Linux-x86_64) asset="kubeconform-linux-amd64.tar.gz"; sum="9bc2bffbf71f261128533edaf912153948b7ff238f9a531ae6d34466ec287883" ;;
  Linux-aarch64) asset="kubeconform-linux-arm64.tar.gz"; sum="1f53fc8e81258197a35e8603054162a5af1de8c5af13746c71ab680d9534ed87" ;;
  *) echo "install-tools: unsupported platform $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

if [ -x "$dest/kubeconform" ] && "$dest/kubeconform" -v | grep -qx "$version"; then
  exit 0
fi

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

curl -fsSL -o "$tmp/$asset" "https://github.com/yannh/kubeconform/releases/download/$version/$asset"
echo "$sum  $tmp/$asset" | shasum -a 256 -c - > /dev/null
tar -xzf "$tmp/$asset" -C "$tmp" kubeconform
mkdir -p "$dest"
install -m 0755 "$tmp/kubeconform" "$dest/kubeconform"
echo "kubeconform $version installed in $dest"
