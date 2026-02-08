# Deployment plan and requirements

## Scope

- Deploy OWASP Dependency-Track to AKS using the official Helm chart, pulled from an internal Helm repository.
- Use an internal Docker registry for images and authenticate via a Kubernetes `imagePullSecret`.
- Expose the UI via Traefik Ingress with a TLS secret created from provided PEM material.
- Use **external Postgres** configuration via `ALPINE_DATABASE_*` env vars.
- Preserve and enforce a stable Dependency-Track encryption key (`secret.key`) to avoid breaking stored encrypted material.

## Key constraints

- Target platform: **GitHub Enterprise Server (GHES)**.
- Artifact tooling must use **v3** actions:
  - `actions/upload-artifact@v3`
  - `actions/download-artifact@v3`
- Avoid GitHub Actions contexts that may not be available on GHES (`runner.*`). Use `$RUNNER_TEMP` for temp paths.

## Workflow behaviour

### Standard deploy (`dtrack_debug=false`)

- Uses `helm upgrade --install ... --wait --timeout <HELM_TIMEOUT> --atomic`.
- On failure, Helm rolls back and cleans up.

### Debug deploy (`dtrack_debug=true`)

- Enables extra diagnostics jobs and captures artifacts.
- **Deliberately omits `--atomic`** during Helm deploy so that failed resources remain in-cluster for inspection.
- The `cluster-debug-bundle` job collects:
  - `kubectl get all`, events, describes
  - Pod logs (with basic redaction for common password patterns)
  - Helm status/history/values
  - Rendered Helm values artifact

Operational note: debug runs may require manual cleanup (`helm uninstall`).

## Secret handling model

### 1) Registry credentials

- The workflow creates/updates a `kubernetes.io/dockerconfigjson` secret containing registry auth.
- Only the secret reference is used by workloads; credentials are not written to Helm values.

### 2) TLS certificate

- The workflow creates/updates the TLS secret from raw PEM strings (`WILDCARD_CRT`, `WILDCARD_KEY`).
- The workflow validates the PEM header is present (catches base64/PFX/DER mistakes early).

### 3) Postgres

- Uses:
  - `ALPINE_DATABASE_URL` (JDBC preferred)
  - `ALPINE_DATABASE_USERNAME`
  - `ALPINE_DATABASE_PASSWORD`
- Guardrail: `ALPINE_DATABASE_URL` must not embed username/password.

### 4) Dependency-Track secret key (`secret.key`)

- Master value is supplied via `DTRACK_SECRET_KEY` (base64).
- The workflow checks the existing in-cluster secret (if present) and **fails on drift**.
- If missing and `DTRACK_SECRET_KEY_CREATE=true`, the secret is created.

Remediation for drift:
- **Preferred**: update your mastered value to match the in-cluster secret (export it once, store it in Key Vault, sync to GitHub).
- **Avoid rotation** unless you understand the impact: rotating `secret.key` can break access to previously encrypted data.

## Authentication

- Default: Azure service principal via `az login --service-principal`.
- Advanced option (documented only): OIDC-based login can be introduced later (requires federated credentials and runner/network considerations).

