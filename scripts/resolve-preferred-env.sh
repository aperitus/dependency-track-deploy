#!/usr/bin/env bash
set -euo pipefail

# Resolves a set of keys by preferring an Environment Variable value over an Environment Secret value.
#
# Expected inputs:
#   For each KEY in KEYS:
#     - KEY__VAR    (from vars.KEY)
#     - KEY__SECRET (from secrets.KEY)
#
# Output:
#   - Writes resolved KEY=... to $GITHUB_ENV
#   - Logs source used: var | secret | empty
#   - Prints actual value only when:
#       a) source is 'var', and
#       b) key does not look sensitive

is_sensitive_key() {
  local k="$1"
  k="${k^^}"
  [[ "$k" == *"SECRET"* ]] && return 0
  [[ "$k" == *"PASSWORD"* ]] && return 0
  [[ "$k" == *"TOKEN"* ]] && return 0
  [[ "$k" == *"KEY"* ]] && return 0
  [[ "$k" == *"CRT"* ]] && return 0
  [[ "$k" == *"CERT"* ]] && return 0
  return 1
}

log_resolution() {
  local key="$1" src="$2" val="$3"

  if [[ "$src" == "empty" ]]; then
    echo "resolve: ${key} -> empty"
    return
  fi

  if [[ "$src" == "secret" ]]; then
    # Never print secret values.
    echo "resolve: ${key} -> secret (redacted; len=${#val})"
    return
  fi

  # src == var
  if is_sensitive_key "$key"; then
    echo "resolve: ${key} -> var (redacted; len=${#val})"
  else
    echo "resolve: ${key} -> var (${val})"
  fi
}

resolve_key() {
  local key="$1"
  local var_name="${key}__VAR"
  local sec_name="${key}__SECRET"

  local var_val="${!var_name-}"
  local sec_val="${!sec_name-}"

  local chosen=""
  local src="empty"

  if [[ -n "${var_val}" ]]; then
    chosen="${var_val}"
    src="var"
  elif [[ -n "${sec_val}" ]]; then
    chosen="${sec_val}"
    src="secret"
  else
    chosen=""
    src="empty"
  fi

  log_resolution "$key" "$src" "$chosen"

  # Export resolved value.
  # Note: writing an empty value to GITHUB_ENV is ok; downstream checks can enforce required-ness.
  {
    echo "${key}<<__EOF__"
    echo "${chosen}"
    echo "__EOF__"
    echo "RESOLVED_SOURCE_${key}=${src}"
  } >> "${GITHUB_ENV}"
}

main() {
  if [[ $# -lt 1 ]]; then
    echo "usage: $0 KEY [KEY ...]" >&2
    exit 2
  fi
  for k in "$@"; do
    resolve_key "$k"
  done
}

main "$@"
