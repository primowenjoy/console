#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 VERSION --plugin-dir DIR [--push]"
}

if [[ ${1:-} == --help || ${1:-} == -h ]]; then
  usage
  exit 0
fi
if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi
version=$1
shift
number='(0|[1-9][0-9]*)'
identifier="($number|[0-9]*[A-Za-z-][0-9A-Za-z-]*)"
semver="^$number[.]$number[.]$number(-$identifier([.]$identifier)*)?$"
if [[ ! $version =~ $semver || ${#version} -gt 128 ]]; then
  echo "VERSION must be a SemVer usable as a Docker tag (no build metadata, at most 128 characters)" >&2
  exit 1
fi

plugin_dir=
push=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --plugin-dir)
      if [[ $# -lt 2 || -z $2 || $2 == --* ]]; then
        usage >&2
        exit 1
      fi
      plugin_dir=$2
      shift 2
      ;;
    --push)
      push=true
      shift
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z $plugin_dir ]]; then
  usage >&2
  exit 1
fi
plugin=$(git -C "$plugin_dir" rev-parse --show-toplevel)
if [[ ! -f "$plugin/hack/console-web.mjs" ]]; then
  echo "Missing hack/console-web.mjs in $plugin" >&2
  exit 1
fi
root=$(cd "$(dirname "$0")/.." && pwd)
for checkout in "$root" "$plugin"; do
  if [[ -n $(git -C "$checkout" status --porcelain) ]]; then
    echo "Commit changes before building from $checkout" >&2
    exit 1
  fi
done
revision=$(git -C "$root" rev-parse HEAD)
plugin_revision=$(git -C "$plugin" rev-parse HEAD)
work=$(mktemp -d "${TMPDIR:-/tmp}/console-canary-image.XXXXXX")
trap 'rm -rf "$work"' EXIT
context="$work/console"
node "$plugin/hack/console-web.mjs" stage --console "$root" --output "$context"
echo "Console source $revision, Canary plugin source $plugin_revision"
output=--load
if $push; then
  output=--push
fi

docker buildx build --platform linux/amd64 --file "$context/Dockerfile" \
  --build-arg GOPROXY \
  --tag "harbor.4pd.io/hardcore-tech/console-canary:$version" \
  --label "org.opencontainers.image.source=https://github.com/primowenjoy/console" \
  --label "org.opencontainers.image.revision=$revision" \
  --label "dev.modelsphere.canary.plugin.revision=$plugin_revision" \
  --label "org.opencontainers.image.version=$version" \
  "$output" "$context"
