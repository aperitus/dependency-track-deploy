# Changelog

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
