#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  collect_issue_candidates.sh --repo <owner/repo> --title <title> --issue-query <query> [--limit <n>] [--out <path>]
USAGE
}

repo=""
title=""
issue_query=""
limit="100"
out=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --repo)
      repo="$2"
      shift 2
      ;;
    --title)
      title="$2"
      shift 2
      ;;
    --issue-query)
      issue_query="$2"
      shift 2
      ;;
    --limit)
      limit="$2"
      shift 2
      ;;
    --out)
      out="$2"
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

if [[ -z "$repo" || -z "$title" || -z "$issue_query" ]]; then
  usage
  exit 1
fi

fields="number,title,body,state,labels,url,createdAt,updatedAt"

all_open_json="$(gh issue list --repo "$repo" --state open --limit "$limit" --json "$fields")"
feature_open_json="$(gh issue list --repo "$repo" --state open --label type/feature --limit "$limit" --json "$fields")"
planned_open_json="$(gh issue list --repo "$repo" --state open --label status/planned --limit "$limit" --json "$fields")"
in_progress_open_json="$(gh issue list --repo "$repo" --state open --label status/in-progress --limit "$limit" --json "$fields")"
query_json="$(gh issue list --repo "$repo" --state all --search "$issue_query" --limit "$limit" --json "$fields")"
title_json="$(gh issue list --repo "$repo" --state all --search "$title" --limit "$limit" --json "$fields")"

merged_json="$({
  jq -s 'add | unique_by(.number) | sort_by(.updatedAt) | reverse' \
    <(printf '%s\n' "$all_open_json") \
    <(printf '%s\n' "$feature_open_json") \
    <(printf '%s\n' "$planned_open_json") \
    <(printf '%s\n' "$in_progress_open_json") \
    <(printf '%s\n' "$query_json") \
    <(printf '%s\n' "$title_json")
})"

if [[ -n "$out" ]]; then
  mkdir -p "$(dirname "$out")"
  printf '%s\n' "$merged_json" > "$out"
fi

total_count="$(printf '%s\n' "$merged_json" | jq 'length')"
query_count="$(printf '%s\n' "$query_json" | jq 'length')"
title_count="$(printf '%s\n' "$title_json" | jq 'length')"

echo "== Candidate =="
echo "repo: $repo"
echo "title: $title"
echo "issue_query: $issue_query"
echo

echo "== Issue Corpus =="
echo "total_candidates: $total_count"
echo "query_seed_matches: $query_count"
echo "title_seed_matches: $title_count"
if [[ -n "$out" ]]; then
  echo "output_file: $out"
fi
echo

echo "== Top Candidates =="
printf '%s\n' "$merged_json" | jq -r '.[0:25][] | "#\(.number) [\(.state)] \(.title) | labels: \([.labels[]?.name] | join(", ")) | \(.url)"'
