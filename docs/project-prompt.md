# Project Prompt — Dependency-Track App Repo (AKS via GHES Actions)

You are operating on the repository that owns the **Dependency-Track** application deployment to an AKS cluster.

## Constraints
- Deployment must run via **GitHub Actions** on a **self-hosted runner**.
- GHES is private/firewalled: do **not** use Entra OIDC federation. Authenticate with **Service Principal + client secret**.
- Do **not** install/upgrade ingress-nginx here (owned by the baseline repo).
- All container images must be pulled from **Nexus**:
  - Override Dependency-Track images to Nexus.
  - Create/update a `kubernetes.io/dockerconfigjson` Secret named `IMAGE_PULL_SECRET_NAME` in namespace `dependency-track`.
- TLS:
  - Create/update `INGRESS_TLS_SECRET_NAME` in namespace `dependency-track` from `WILDCARD_CRT/WILDCARD_KEY`.
- Workflow must be idempotent and safe to rerun.
- Never print secrets to logs:
  - avoid shell tracing
  - write secret material to temp files only
  - use `umask 077` and clean up files
- Keep sensitive app config out of Helm history by storing it in `dependency-track-app-config` and referencing it from values.
- Helm must use pinned chart versions and `--wait --atomic --timeout`.

## Output expectations
- Keep values generation minimal and deterministic.
- Use readable multi-line YAML blocks.
