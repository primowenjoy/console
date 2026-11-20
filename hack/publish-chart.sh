#!/usr/bin/env bash
set -euo pipefail

usage() {
  echo "Usage: $0 VERSION [--output DIR] [--push]"
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

output=$PWD
push=false
while [[ $# -gt 0 ]]; do
  case $1 in
    --output)
      if [[ $# -lt 2 || -z $2 || $2 == --* ]]; then
        usage >&2
        exit 1
      fi
      output=$2
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

root=$(cd "$(dirname "$0")/.." && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/console-chart.XXXXXX")
trap 'rm -rf "$work"' EXIT

cp -R "$root/helm/console" "$work/chart"
if [[ ! -f "$work/chart/Chart.lock" ]]; then
  echo "Console chart requires Chart.lock" >&2
  exit 1
fi
rm -rf "$work/chart/charts"
helm dependency build "$work/chart" --skip-refresh

awk '
  /^image:/ { image = 1; print; next }
  /^[^[:space:]#]/ { image = 0 }
  image && /^  repository:/ {
    print "  repository: harbor.4pd.io/hardcore-tech/console-canary"
    updated++
    next
  }
  { print }
  END { if (updated != 1) exit 1 }
' "$work/chart/values.yaml" > "$work/values.yaml"
mv "$work/values.yaml" "$work/chart/values.yaml"

helm package "$work/chart" --version "$version" --app-version "$version" --destination "$work"
archive="console-$version.tgz"
helm lint "$work/$archive" --strict

mkdir -p -- "$output"
cp "$work/$archive" "$output/$archive"
echo "Chart retained at $output/$archive"

if $push; then
  helm push "$output/$archive" oci://harbor.4pd.io/hardcore-tech/charts
fi
