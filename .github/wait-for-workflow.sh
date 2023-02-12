#!/usr/bin/env bash

set -euo pipefail

check_conclusion() {
  local retries count run_data status

  retries=$1
  shift

  # initial sleep in case items take a second to get onto the queue
  sleep 5

  count=0
  wait=1
  run_data="$(get_run)"
  until status="$(jq <<<"$run_data" -r .status)" && [[ $status == "completed" ]]; do
    wait=$((wait >= 15 ? 15 : 2 ** count))
    count=$((count+1))
    if ((count < retries)); then
      printf "Retry %d/%d run status=%s, checking again in %s seconds...\n" "$count" "$retries" "$status" "$wait" >&2
      sleep $wait
      run_data="$(get_run)"
    else
      printf "Retry %d/%d run status=%s, no more retries left.\n" "$count" "$retries" "$status" >&2
      return 1
    fi
  done

  conclusion="$(jq <<<"$run_data" -r .conclusion)"
  printf "Retry %d/%d run status=%s, conclusion=%s. Completed.\n" "$count" "$retries" "$status" "$conclusion" >&2
  case $conclusion in
  success) return 0 ;;
  *) return 1 ;;
  esac
}

get_run() {
  curl -s -H "Authorization: Bearer ${GITHUB_TOKEN}" "https://api.github.com/repos/${GITHUB_REPOSITORY}/actions/runs" |
    jq --arg head_branch "${WAIT_BRANCH}" \
      --arg github_sha "${WAIT_SHA}" \
      --arg github_event "${WAIT_EVENT}" \
      --arg workflow_name "${WAIT_WORKFLOW_NAME}" \
      '.workflow_runs | map(select(.head_branch == $head_branch and .event == $github_event and .name == $workflow_name and .head_sha == $github_sha)) | sort_by(.created_at) | reverse | .[0]'
}

check_conclusion 300
exit $?
