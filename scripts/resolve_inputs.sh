#!/usr/bin/env bash
set -euo pipefail

# Resolve an input value, preferring GitHub Environment Variables (vars.<NAME>)
# over GitHub Environment Secrets (secrets.<NAME>).
#
# Workflow must provide candidate values via env:
#   RESOLVE_VAR_<NAME> and RESOLVE_SECRET_<NAME>
#
# Result is exported to GITHUB_ENV as:
#   <NAME>=<value>
#
# Logging behaviour:
# - If the chosen value is from vars, we print the value (unless marked sensitive).
# - If from secrets, we never print the value.
# - If missing, we log that it is empty.

_note()  { echo "::notice title=$1::$2"; }
_warn()  { echo "::warning title=$1::$2"; }
_error() { echo "::error title=$1::$2"; }

resolve_pref_var_then_secret() {
  local name="$1"
  local sensitive="${2:-false}"
  local default_value="${3:-}"

  local var_key="RESOLVE_VAR_${name}"
  local sec_key="RESOLVE_SECRET_${name}"

  # shellcheck disable=SC2154
  local var_val="${!var_key-}"
  # shellcheck disable=SC2154
  local sec_val="${!sec_key-}"

  local chosen_src=""
  local chosen_val=""

  if [[ -n "${var_val}" ]]; then
    chosen_src="vars.${name}"
    chosen_val="${var_val}"
  elif [[ -n "${sec_val}" ]]; then
    chosen_src="secrets.${name}"
    chosen_val="${sec_val}"
  else
    chosen_src="empty"
    chosen_val="${default_value}"  # may still be empty
  fi

  # Export to later steps
  {
    echo "${name}=${chosen_val}"
  } >> "${GITHUB_ENV}"

  # Log what we did (never leak secrets)
  if [[ "${chosen_src}" == "empty" ]]; then
    if [[ -n "${default_value}" ]]; then
      _note "Input defaulted" "${name}: empty (vars/secrets missing) -> using default value"
    else
      _warn "Input missing" "${name}: empty (vars.${name} and secrets.${name} not set)"
    fi
    return 0
  fi

  # Always redact values sourced from secrets, even if the key is normally non-sensitive.
  if [[ "${chosen_src}" == secrets.* ]]; then
    _note "Input resolved" "${name}: using ${chosen_src} = <redacted>"
    return 0
  fi

  if [[ "${sensitive}" == "true" ]]; then
    _note "Input resolved" "${name}: using ${chosen_src} = <redacted>"
  else
    _note "Input resolved" "${name}: using ${chosen_src} = ${chosen_val}"
  fi
}

require_non_empty() {
  local name="$1"
  # shellcheck disable=SC2154
  local val="${!name-}"
  if [[ -z "${val}" ]]; then
    _error "Missing required input" "${name} is required but is empty"
    exit 1
  fi
}
