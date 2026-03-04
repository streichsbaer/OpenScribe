#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  verify_issue.sh --repo <owner/repo> --issue <number-or-url>
USAGE
}

repo=""
issue=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --issue)
      issue="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$repo" || -z "$issue" ]]; then
  usage
  exit 1
fi

gh issue view "$issue" \
  --repo "$repo" \
  --json number,title,state,labels,url \
  --jq '"#\(.number) [\(.state)] \(.title)\nlabels: \([.labels[]?.name] | join(", "))\nurl: \(.url)"'
