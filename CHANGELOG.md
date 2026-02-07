# Changelog

## v0.2.7

- Fix: apply `--admin` flag consistently in debug job when `use_admin_credentials=true`.

## v0.2.6

- Fix: debug-artifacts job now respects `use_admin_credentials`.

## v0.2.4

- Docs: fix changelog rendering for `$RUNNER_TEMP`.

## v0.2.3

- Fix: resolve `AZURE_CONFIG_DIR` and `KUBECONFIG` using `runner.temp` (prevents literal `$RUNNER_TEMP` paths).

## v0.2.2 (2026-02-07)

- Added **Dependency-Track Deploy — Authoritative Design & Compliance** document into the repository.
- Simplified database configuration: **JDBC only** via `ALPINE_DATABASE_URL` (removed legacy URL conversion and `DTRACK_DB_URL`).
- Made secret-key mastery explicit and mandatory:
  - `DTRACK_SECRET_KEY` is required (mastered externally).
  - Workflow creates the Kubernetes secret if missing and **fails on drift** with verbose remediation guidance.
- Split debugging output into a separate job:
  - New `debug-artifacts` job runs when `debug=true` and uses `if: always()` to upload debug artefacts even if deployment fails.
  - Uploads `values.generated.yaml`, Helm status/values, kubectl diagnostics, events, and logs (no secrets).
- Standardised workflow inputs:
  - `debug` replaces `dtrack_debug`.

## v0.1.13 (2026-02-06)

- Baseline deploy workflow with vars-first fallback.
- Helm deployment of Dependency-Track using Traefik ingress.
- Secret key creation/verification support.
