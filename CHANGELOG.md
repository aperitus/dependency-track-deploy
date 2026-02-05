# Changelog


## v0.1.11
- Added `DTRACK_SECRET_KEY` (GitHub Environment Secret) support to **master** the Dependency-Track secret key in Key Vault and keep it stable across redeploys/migrations.
  - If `DTRACK_SECRET_KEY` is set, the workflow creates the Kubernetes secret (if missing) and **verifies it matches** on every run.
  - If the cluster secret exists but differs, the workflow fails to prevent accidental crypto key rotation.
  - When `DTRACK_SECRET_KEY` is set, the workflow forces `DTRACK_SECRET_KEY_CREATE=false` and sets a default `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` if empty.
- README updated with generation and migration-safe export guidance.


## v0.1.10
- Fixed a common deployment failure when `common.secretKey.existingSecretName` is set but the referenced secret does not exist.
  - If `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` is set, the workflow now creates the secret **once** (only if missing) with a random 32-byte key.
  - If `DTRACK_SECRET_KEY_CREATE=true`, the workflow now forces `existingSecretName` empty in the rendered values to avoid accidental secret mounts.


## v0.1.9
- Regenerated the **base** repository package (no admin-password bootstrap logic and no backup placeholders).


## v0.1.8
- Simplified registry handling: all Dependency-Track images now use `REGISTRY_SERVER` (no per-component registry overrides).
- Replaced `NEXUS_DOCKER_SERVER`/`NEXUS_DOCKER_USERNAME`/`NEXUS_DOCKER_PASSWORD` with `REGISTRY_SERVER`/`REGISTRY_USERNAME`/`REGISTRY_PASSWORD` throughout the workflow and docs.

## v0.1.7
- Database configuration now prefers `ALPINE_DATABASE_URL` / `ALPINE_DATABASE_USERNAME` / `ALPINE_DATABASE_PASSWORD` (external Postgres). `DTRACK_DB_URL` is supported as a legacy fallback.
- Added automatic conversion of libpq URLs (`postgres://...`) to JDBC (`jdbc:postgresql://...`) and enforces `sslmode=require` when absent.
- Early debug output no longer prints non-JDBC DB URLs to avoid accidental credential leakage.

## v0.1.6
- Fixed workflow failure: export ENV_FILE before Python reads it in the app-config secret step.
- Added a normalisation step to set AZURE_CONFIG_DIR and KUBECONFIG to resolved ${RUNNER_TEMP} paths (job-level values use literal $RUNNER_TEMP).

## v0.1.4
- Added a configuration reference table in README with descriptions and examples for all workflow inputs and environment keys.

## v0.1.3
- Replaced the resolver script with inline vars-first fallback expressions (e.g. `vars.KEY != '' && vars.KEY || secrets.KEY`).
- Added required `DTRACK_DB_URL` (Postgres JDBC URL) and maps it to `ALPINE_DATABASE_URL` in the API server env.
- Removed resolver scripts from the repository.

## v0.1.2
- Fixed invalid YAML in the workflow (heredoc Python blocks are correctly indented).
- Added `workflow_dispatch` **environment** input with `dev | preprod | prod` options, and wired the job to the selected GitHub Environment.
- Resolver step supported the requested `RESOLVE_VAR_*` / `RESOLVE_SECRET_*` naming convention.

## v0.1.1
- Reused the tested **Azure login / AKS credentials / Helm install** step patterns from `deploy-traefik.yaml` (az cli login + kubelogin spn conversion).
- Added pre-run resolver (`vars` preferred over `secrets`) and logs source selection without leaking secret values.
- Helm timeout parsing aligned with Traefik workflow (`10` -> `10m`).

## v0.1.0
- Initial repository skeleton for deploying Dependency-Track behind an existing Traefik ingress.
