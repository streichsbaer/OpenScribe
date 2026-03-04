#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  preflight_check.sh --repo <owner/repo> --title <title> [--issue-query <query>] [--code-query <query>] [--paths "Sources Tests site-docs docs"] [--limit <n>] [--strict-no-create] [--issues-only] [--skip-issue-search] [--issue-match-count <n>] [--issue-evidence <text>] [--skip-code-search] [--code-match-count <n>] [--code-evidence <text>]
USAGE
}

repo=""
title=""
code_query=""
issue_query=""
paths="Sources Tests site-docs docs"
limit="100"
strict_no_create="false"
issues_only="false"
skip_issue_search="false"
issue_match_count_override=""
issue_evidence=""
skip_code_search="false"
code_match_count_override=""
code_evidence=""

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
    --code-query)
      code_query="$2"
      shift 2
      ;;
    --issue-query)
      issue_query="$2"
      shift 2
      ;;
    --paths)
      paths="$2"
      shift 2
      ;;
    --limit)
      limit="$2"
      shift 2
      ;;
    --strict-no-create)
      strict_no_create="true"
      shift 1
      ;;
    --issues-only)
      issues_only="true"
      shift 1
      ;;
    --skip-issue-search)
      skip_issue_search="true"
      shift 1
      ;;
    --issue-match-count)
      issue_match_count_override="$2"
      shift 2
      ;;
    --issue-evidence)
      issue_evidence="$2"
      shift 2
      ;;
    --skip-code-search)
      skip_code_search="true"
      shift 1
      ;;
    --code-match-count)
      code_match_count_override="$2"
      shift 2
      ;;
    --code-evidence)
      code_evidence="$2"
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

if [[ -z "$repo" || -z "$title" ]]; then
  usage
  exit 1
fi

if [[ "$skip_issue_search" != "true" && -z "$issue_query" ]]; then
  echo "Missing required argument: --issue-query (unless --skip-issue-search is set)" >&2
  usage
  exit 1
fi

if [[ "$skip_issue_search" == "true" && -z "$issue_match_count_override" ]]; then
  echo "Missing required argument: --issue-match-count (when --skip-issue-search is set)" >&2
  usage
  exit 1
fi

if [[ "$issues_only" != "true" && "$skip_code_search" != "true" && -z "$code_query" ]]; then
  echo "Missing required argument: --code-query (unless --skip-code-search is set)" >&2
  usage
  exit 1
fi

if [[ -n "${ZSH_VERSION-}" ]]; then
  path_array=(${=paths})
else
  read -r -a path_array <<< "$paths"
fi

echo "== Candidate =="
echo "title: $title"
echo "repo: $repo"
if [[ "$issues_only" == "true" ]]; then
  echo "mode: issues-only"
elif [[ -n "$code_query" ]]; then
  echo "code_query: $code_query"
else
  echo "code_query: <skipped>"
fi
if [[ "$skip_issue_search" == "true" ]]; then
  echo "issue_query: <skipped>"
else
  echo "issue_query: $issue_query"
fi
echo

echo "== Existing issues =="
if [[ "$skip_issue_search" == "true" ]]; then
  issue_matches="$issue_evidence"
  if [[ -n "$issue_matches" ]]; then
    printf '%s\n' "$issue_matches"
  else
    echo "<skipped: provided by explorer issue evidence>"
  fi
  issue_count="$issue_match_count_override"
else
  issue_json_from_query="$(gh issue list \
    --repo "$repo" \
    --state all \
    --search "$issue_query" \
    --limit "$limit" \
    --json number,title,state,labels,url)"
  issue_json_from_title="$(gh issue list \
    --repo "$repo" \
    --state all \
    --search "$title" \
    --limit "$limit" \
    --json number,title,state,labels,url)"

  issue_json_merged="$(
    jq -s 'add | unique_by(.number)' \
      <(printf '%s\n' "$issue_json_from_query") \
      <(printf '%s\n' "$issue_json_from_title")
  )"
  issue_matches="$(printf '%s\n' "$issue_json_merged" | jq -r '.[] | "#\(.number) [\(.state)] \(.title) | labels: \([.labels[]?.name] | join(", ")) | \(.url)"')"
  if [[ -n "$issue_matches" ]]; then
    printf '%s\n' "$issue_matches"
  fi
  issue_count="$(printf '%s\n' "$issue_json_merged" | jq 'length')"
fi

if [[ "$skip_issue_search" == "true" && "${issue_count:-0}" -gt 0 ]]; then
  if ! printf '%s\n' "$issue_evidence" | rg -q "https?://"; then
    echo "issue_evidence_url_check: missing issue URL in --issue-evidence for duplicate match." >&2
    if [[ "$strict_no_create" == "true" ]]; then
      echo "strict_no_create: blocking issue creation until duplicate evidence includes issue URL." >&2
      exit 6
    fi
  fi
fi

classification=""
decision=""
code_count="0"

print_decision() {
  echo
  echo "== Decision =="
  echo "code_match_count: ${code_count:-0}"
  echo "issue_match_count: ${issue_count:-0}"
  echo "classification: $classification"
  echo "decision: $decision"
}

if [[ "${issue_count:-0}" -gt 0 ]]; then
  classification="duplicate"
  decision="DO_NOT_CREATE"

  echo
  echo "== Codebase matches =="
  echo "<skipped: duplicate found in issue gate>"

  print_decision

  if [[ "$strict_no_create" == "true" ]]; then
    echo "strict_no_create: blocking issue creation until user confirms override."
    echo "operator_prompt: existing issue coverage found. create a new ticket anyway? (yes/no)"
    exit 3
  fi

  exit 0
fi

if [[ "$issues_only" == "true" ]]; then
  classification="needs-code-check"
  decision="REQUIRES_CODE_CHECK"

  echo
  echo "== Codebase matches =="
  echo "<skipped: issues-only gate requested>"

  print_decision

  if [[ "$strict_no_create" == "true" ]]; then
    echo "strict_no_create: blocking issue creation until code check is complete."
    exit 4
  fi

  exit 0
fi

echo
echo "== Codebase matches =="
if [[ "$skip_code_search" == "true" ]]; then
  code_matches="$code_evidence"
  if [[ -n "$code_matches" ]]; then
    printf '%s\n' "$code_matches"
  else
    echo "<skipped: provided by explorer evidence>"
  fi
  if [[ -n "$code_match_count_override" ]]; then
    code_count="$code_match_count_override"
  else
    code_count="0"
  fi
else
  if command -v rg >/dev/null 2>&1; then
    code_matches="$(rg -n -S -i "$code_query" "${path_array[@]}" || true)"
  else
    code_matches="$(grep -R -n -i "$code_query" "${path_array[@]}" || true)"
  fi
  if [[ -n "$code_matches" ]]; then
    printf '%s\n' "$code_matches"
  fi
  code_count="$(printf '%s\n' "$code_matches" | sed '/^[[:space:]]*$/d' | wc -l | tr -d ' ')"
fi

if [[ "${code_count:-0}" -gt 0 ]]; then
  classification="already-implemented"
  decision="DO_NOT_CREATE"
else
  classification="new"
  decision="CAN_CREATE"
fi

print_decision

if [[ "$strict_no_create" == "true" && "$decision" == "DO_NOT_CREATE" ]]; then
  echo "strict_no_create: blocking issue creation until user confirms override."
  echo "operator_prompt: existing implementation coverage found. create a new ticket anyway? (yes/no)"
  exit 3
fi
