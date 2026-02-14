# Dependency-Track Deploy — Authoritative Design & Compliance

**Document purpose:** This document is the single authoritative reference for how the `dependency-track-deploy` repository is designed to behave, what it consumes (inputs), what it produces (cluster resources), and the compliance constraints it must adhere to.

**Last updated:** 2026-02-08  
**Repository:** `dependency-track-deploy`  
**Deployment target:** AKS, GHES GitHub Actions, Namespace `dependency-track`  
**Ingress:** Traefik (managed by separate repository; out of scope here)

---

## 1. BLUF

- This repository deploys **Dependency-Track** to AKS using **Helm + kubectl** executed in **GitHub Actions** (GHES).
- It **does not** deploy or manage the ingress controller (Traefik is assumed pre-installed and is a separate source-of-truth repo).
- Configuration is **mastered externally** (Key Vault → GitHub Environment vars/secrets via the secret-sync tool). This repository only **consumes** GitHub Environment vars/secrets and must document them precisely.
- The Dependency-Track **secret key** is **mastered in Key Vault** and must be **verified** against the cluster on every run. Any drift is a hard failure with remediation guidance.
- Debug mode is supported via a boolean workflow input. When enabled, **separate debug jobs** must upload troubleshooting artefacts even if the main deploy job fails.

---

## 2. Scope

### In scope
- Deploy Dependency-Track (official chart) into AKS.
- Create/update required Kubernetes secrets in `dependency-track`:
  - Image pull secret (`IMAGE_PULL_SECRET_NAME`) using `REGISTRY_*`
  - TLS secret (`INGRESS_TLS_SECRET_NAME`) from `WILDCARD_CRT`/`WILDCARD_KEY`
  - App config secret (`DTRACK_APP_CONFIG_SECRET_NAME`) providing `ALPINE_DATABASE_*` and other non-sensitive app settings as needed
  - Secret-key secret (name controlled by `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME`), created/verified using `DTRACK_SECRET_KEY` mastered value
- Create/update a Kubernetes `Ingress` (or chart-managed ingress) targeting Traefik using:
  - host: `dtrack.logiki.co.uk`
  - className: `traefik`
  - TLS secret: `INGRESS_TLS_SECRET_NAME`
- Provide debug artefacts and cluster diagnostics when debug is enabled.

### Out of scope
- Traefik installation, upgrade, chart values, or lifecycle (separate repository is authoritative).
- Azure infrastructure provisioning (AKS, Postgres, Key Vault, DNS, Private DNS).
- Terraform resources for Key Vault secrets/vars (mastering happens elsewhere; this repo only consumes).

---

## 3. Non-negotiable constraints

### 3.1 Execution model
- **Do not** use Terraform Helm/Kubernetes providers for chart/resource deployment.
- Helm and kubectl operations must execute in **GitHub Actions**.

### 3.2 GHES authentication to Azure

Baseline mode (must work): **Service Principal + client secret**

- The workflow must log in using `az login --service-principal` with:
  - `DEPLOY_CLIENT_ID`
  - `DEPLOY_SECRET`
  - `AZURE_TENANT_ID`
  - `AZURE_SUBSCRIPTION_ID`
- The workflow must isolate Azure CLI state per-run by using `AZURE_CONFIG_DIR` and clearing any prior auth (`az logout`, `az account clear`).

AKS kubeconfig acquisition (non-admin): **kubelogin SPN conversion**

- The workflow must acquire the kubeconfig using `az aks get-credentials` (Entra auth) and then run:
  - `kubelogin convert-kubeconfig --login=spn --client-id ... --client-secret ... --tenant-id ...`
- The workflow must fail if the resulting kubeconfig still references `command: azurecli` (interactive auth).

Admin credential option

- If `use_admin_credentials=true`, the workflow may use `az aks get-credentials --admin` and **must not** run kubelogin conversion.

OIDC / Entra federation

- GHES is private; treat OIDC as an advanced option.
- Baseline must remain functional without OIDC.

### 3.3 Registry policy (Nexus-only)
- All images must be pulled via the Nexus registry host `REGISTRY_SERVER`.
- The workflow must not depend on `NEXUS_*` variables or per-component registry vars.
- Pull credentials are `REGISTRY_USERNAME` / `REGISTRY_PASSWORD`.

### 3.4 No secret leakage
- Do not print secret values to logs.
- Avoid `set -x` / shell tracing.
- If writing sensitive material to disk (certs/keys), use:
  - `$RUNNER_TEMP` paths
  - restrictive permissions (e.g., `chmod 600`)
  - remove files when no longer needed (best-effort)

---

## 4. Deployment targets

| Item | Value |
|---|---|
| Kubernetes namespace | `dependency-track` |
| Helm release name | `dependency-track` |
| Ingress host | `dtrack.logiki.co.uk` |
| Ingress class | `traefik` |
| Chart | `dependency-track/dependency-track` (official) |
| Images | Pulled from `REGISTRY_SERVER` (Nexus) |

---

## 5. Inputs contract

### 5.1 Workflow dispatch inputs

| Input | Type | Required | Default | Description |
|---|---:|---:|---|---|
| `environment` | choice | Yes | — | GitHub Environment to use: `dev`, `preprod`, `prod` |
| `debug` | boolean | No | `false` | When `true`, enables debug logging and runs separate debug artefact jobs |
| `helm_timeout` | string | No | `15m` | Helm `--timeout` value (debugging may increase this, e.g. `30m`) |

> Note: The workflow must set `environment: ${{ inputs.environment }}` on the job so Environment vars/secrets are applied.

### 5.2 GitHub Environment variables and secrets consumed

**Resolution model:** the workflow uses the simple vars-first fallback:
- `KEY: ${{ vars.KEY != '' && vars.KEY || secrets.KEY }}`

The tables below list **logical keys**. They may be stored as either Environment vars or secrets as appropriate.

#### Azure / AKS access

| Key | Var/Secret | Required | Example | Description |
|---|---|---:|---|---|
| `DEPLOY_CLIENT_ID` | Var | Yes | `00000000-0000-0000-0000-000000000000` | Azure SP application (client) id |
| `DEPLOY_SECRET` | Secret | Yes | `***` | Azure SP client secret |
| `AZURE_TENANT_ID` | Var | Yes | `11111111-1111-1111-1111-111111111111` | Tenant id |
| `AZURE_SUBSCRIPTION_ID` | Var | Yes | `22222222-2222-2222-2222-222222222222` | Subscription id |
| `AKS_RESOURCE_GROUP` | Var | Yes | `rg-aks-uksouth-01` | AKS resource group |
| `AKS_CLUSTER_NAME` | Var | Yes | `aks-uksouth-01` | AKS cluster name |

#### Registry (Nexus)

| Key | Var/Secret | Required | Example | Description |
|---|---|---:|---|---|
| `REGISTRY_SERVER` | Var | Yes | `docker-group-nexus.logiki.co.uk` | Registry host (Nexus) |
| `REGISTRY_USERNAME` | Var | Yes | `svc-nexus-pull` | Registry username |
| `REGISTRY_PASSWORD` | Secret | Yes | `***` | Registry password |

#### Kubernetes secret names

| Key | Var/Secret | Required | Default | Description |
|---|---|---:|---|---|
| `IMAGE_PULL_SECRET_NAME` | Var | Yes | `nexus-pull` | Name of imagePullSecret created in `dependency-track` |
| `INGRESS_TLS_SECRET_NAME` | Var | Yes | `dtrack-wildcard-tls` | Name of TLS secret created in `dependency-track` |
| `DTRACK_APP_CONFIG_SECRET_NAME` | Var | Yes | `dependency-track-app-config` | Name of app-config secret for api-server env vars |
| `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` | Var | Yes | `dtrack-secret-key` | K8s Secret name that will be mounted as secret key |

#### TLS material (ingress)

| Key | Var/Secret | Required | Example (truncated) | Description |
|---|---|---:|---|---|
| `WILDCARD_CRT` | Var/Secret | Yes | `-----BEGIN CERTIFICATE-----…` | PEM certificate (not private) |
| `WILDCARD_KEY` | Secret | Yes | `-----BEGIN PRIVATE KEY-----…` | PEM private key |

#### Database (external Postgres)

| Key | Var/Secret | Required | Example | Description |
|---|---|---:|---|---|
| `ALPINE_DATABASE_MODE` | Var | Yes | `external` | Dependency-Track DB mode |
| `ALPINE_DATABASE_URL` | Var | Yes | `jdbc:postgresql://host:5432/dtrack?sslmode=require` | JDBC URL (must start with `jdbc:postgresql://`) |
| `ALPINE_DATABASE_USERNAME` | Var | Yes | `dtrack_app` | DB username |
| `ALPINE_DATABASE_PASSWORD` | Secret | Yes | `***` | DB password |
| `ALPINE_DATABASE_DRIVER` | Var/Secret | No* | `org.postgresql.Driver` | JDBC driver class. Defaults to `org.postgresql.Driver`. Legacy alias: `DTRACK_ALPINE_DATABASE_DRIVER`. |

*When deploying against **Azure Database for PostgreSQL – Flexible Server**, treat `ALPINE_DATABASE_DRIVER=org.postgresql.Driver` as **required**. We observed successful DB authentication/queries while the API server `/health/*` endpoints returned `503 Service Unavailable` until the driver was explicitly set. Configure it in GitHub Environment variables/secrets (don’t rely on in-cluster `kubectl patch`, which will be overwritten by the next deploy run).

##### Azure Database for PostgreSQL – Flexible Server checklist

Minimum compatibility requirements for a private AKS cluster accessing Flexible Server:

- **TLS required:** JDBC URL must include `sslmode=require` (or stricter) and the server must be configured for SSL (default in Azure).
- **Network path:** ensure **either** VNet integration **or** Private Endpoint connectivity exists from the AKS node subnets to the Flexible Server.
- **DNS resolution:** for Private Endpoint, the `privatelink.postgres.database.azure.com` Private DNS zone must be linked to the AKS VNet so that the server FQDN resolves to a private IP.
- **Firewall:** if using public access, allowlist the AKS egress IPs; for private access, ensure NSGs/UDRs allow egress to the server’s private IP.
- **Authentication:** use a database role that can create/alter tables in the target database (Dependency-Track creates and migrates schema objects on startup).
- **Driver class:** set `ALPINE_DATABASE_DRIVER=org.postgresql.Driver`.

#### App exposure (Traefik)

| Key | Var/Secret | Required | Default | Description |
|---|---|---:|---|---|
| `DTRACK_INGRESS_HOST` | Var | Yes | `dtrack.logiki.co.uk` | Hostname for ingress |
| `DTRACK_INGRESS_CLASS_NAME` | Var | Yes | `traefik` | IngressClass name |
| `DTRACK_INGRESS_ANNOTATIONS_JSON` | Var | No | `{}` | Optional ingress annotations (JSON object) |

#### Chart pinning and image mapping

| Key | Var/Secret | Required | Default | Description |
|---|---|---:|---|---|
| `DTRACK_HELM_REPO_URL` | Var | Yes | `https://dependencytrack.github.io/helm-charts` | Helm repository URL |
| `DTRACK_CHART_VERSION` | Var | Yes | `0.41.0` | Pinned chart version |
| `DTRACK_APISERVER_IMAGE_REPOSITORY` | Var | Yes | `dependencytrack/apiserver` | Repository under `REGISTRY_SERVER` |
| `DTRACK_FRONTEND_IMAGE_REPOSITORY` | Var | Yes | `dependencytrack/frontend` | Repository under `REGISTRY_SERVER` |
| `DTRACK_APISERVER_IMAGE_TAG` | Var | No | (blank) | Optional override (else chart default) |
| `DTRACK_FRONTEND_IMAGE_TAG` | Var | No | (blank) | Optional override (else chart default) |
| `DTRACK_SECRET_KEY_CREATE` | Var | No | `false` | Rendered into Helm values (`common.secretKey.createSecret`). Wh...

#### Secret key mastery (Key Vault mastered)

| Key | Var/Secret | Required | Example | Description |
|---|---|---:|---|---|
| `DTRACK_SECRET_KEY` | Secret | Yes | `base64…` | Mastered secret-key material (base64). Used to create/verify K8s secret data. |

> `DTRACK_SECRET_KEY` must be treated as sensitive. The workflow must not echo it.

---

## 6. Deployment behaviour

### 6.1 Idempotent resource creation/update
The workflow must be safe to re-run and should implement:
- Namespace creation: `kubectl create ns ... --dry-run=client -o yaml | kubectl apply -f -`
- Image pull secret: create/apply with dockerconfigjson
- TLS secret: create/apply using temporary files for cert/key
- App config secret: create/apply from env file (no logging of secrets)

### 6.2 Helm contract
- Must use pinned chart version and robust flags:
  - `helm upgrade --install`
  - `--namespace dependency-track`
  - `--wait --timeout $HELM_TIMEOUT`
  - `--atomic` is **enabled by default**, but is **disabled when `debug=true`** so that failed resources remain available for post-failure capture in `debug-artifacts`.
- Values must:
  - Set ingress class and host
  - Bind TLS to `INGRESS_TLS_SECRET_NAME`
  - Override image registry to `REGISTRY_SERVER` for all components
  - Use `imagePullSecrets` referencing `IMAGE_PULL_SECRET_NAME`
  - Reference the app-config secret for environment variables
  - Reference the frontend config secret for OIDC client environment variables (`frontend.extraEnvFrom`)
  - Optionally write `ALPINE_OIDC_*` keys into the app-config secret **only when** `DTRACK_OIDC_ENABLED=true` (omit entirely when disabled)

### 6.3 Optional: Dependency-Track OIDC connector (application authentication)

This is **not** Azure login OIDC. This is Dependency-Track's **application-level** OIDC connector used for user authentication.

**Gate:**
- If `DTRACK_OIDC_ENABLED` (vars-first fallback) evaluates to the string "true" (case-insensitive), the workflow writes `ALPINE_OIDC_*` keys into the app-config env file (`${RUNNER_TEMP}/dtrack.env`) and applies the Kubernetes secret `${DTRACK_APP_CONFIG_SECRET_NAME}`.
- If disabled or unset, the workflow must **not** write any `ALPINE_OIDC_*` keys to avoid drift.


**Frontend client configuration:**
- Dependency-Track's frontend requires `OIDC_*` environment variables (client config) in addition to the API server's `ALPINE_OIDC_*` configuration.
- The workflow creates/updates a separate Kubernetes secret `${DTRACK_FRONTEND_CONFIG_SECRET_NAME}`:
  - When `DTRACK_OIDC_ENABLED=true`, it writes `OIDC_ISSUER` and `OIDC_CLIENT_ID` (and optional `OIDC_FLOW`, `OIDC_SCOPE`, `OIDC_LOGIN_BUTTON_TEXT`) into `${RUNNER_TEMP}/dtrack-frontend.env` and applies the secret.
  - When disabled, it still ensures the secret exists (empty) so Helm upgrades are deterministic.
- Helm values must wire this secret into the frontend via `frontend.extraEnvFrom`.

**Inputs (vars-first fallback):**
- `DTRACK_OIDC_ENABLED` (`true`/`false` string)
- `DTRACK_OIDC_ISSUER` (e.g. `https://login.microsoftonline.com/<tenantId>/v2.0`)
- `DTRACK_OIDC_CLIENT_ID` (Entra application client ID)
- `DTRACK_OIDC_USER_CLAIM` (default: `preferred_username`)
- `DTRACK_OIDC_USER_PROVISIONING` (`true`/`false` string; written into the app-config secret)
- `DTRACK_OIDC_TEAM_SYNCHRONIZATION` (`true`/`false` string; written into the app-config secret)
- `DTRACK_OIDC_TEAMS_CLAIM` (default: `groups`)

**Required behaviour:**
- When enabled, fail fast if any required OIDC inputs are missing.
- Never print these values to logs; only write to the app-config env file (`${RUNNER_TEMP}/dtrack.env`) and apply via `kubectl create secret --from-env-file`.

---

## 7. Secret key mastery and drift enforcement (mandatory)

### 7.1 Purpose of the secret key
Dependency-Track uses a server-side secret key for cryptographic operations (signing/encryption). This key must be stable over time.

The chart also exposes `common.secretKey.createSecret`. In this deployment, secret material is mastered via `DTRACK_SECRET_KEY`, so the workflow forces `DTRACK_SECRET_KEY_CREATE=false` to prevent Helm from generating a different key.

### 7.2 Kubernetes secret format
The K8s secret must exist in `dependency-track` namespace and contain base64-encoded key data. The chart commonly expects `secret.key` (and some templates use `secretKey`).

Example:

```yaml
apiVersion: v1
kind: Secret
metadata:
  name: dtrack-secret-key
  namespace: dependency-track
type: Opaque
data:
  secret.key: <BASE64_VALUE>
```

### 7.3 Drift policy (hard fail)
On every run, the workflow must:
1. Read `DTRACK_SECRET_KEY` from GitHub Environment secret.
2. Ensure K8s secret `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` exists.
   - If missing: create it using `DTRACK_SECRET_KEY` as the `data.secret.key` value.
3. Verify that the existing K8s secret `data.secret.key` matches `DTRACK_SECRET_KEY`.
   - If mismatch: **fail** the workflow with a verbose explanation and remediation guidance.

### 7.4 Required failure message content (no secret leakage)
When drift is detected, the workflow must:
- name the secret and namespace
- explain that rotation is unsafe / indicates conflicting sources of truth
- provide remediation options:

**Remediation (example):**
- **Option A (recommended):** Import the *current cluster value* into Key Vault (so mastering matches runtime):
  1) Export cluster value (base64):
     - `kubectl -n dependency-track get secret <name> -o jsonpath='{.data.secret\.key}'`
  2) Update Key Vault / GitHub Environment secret `DTRACK_SECRET_KEY` to that exact base64 string.
  3) Re-run workflow.
- **Option B (intentional rotation / redeploy):** You must manually clear cluster state before redeploy:
  - Delete the secret key secret: `kubectl -n dependency-track delete secret <name>`
  - If you intend a full reset, also remove the application data state that depends on the key (explicitly controlled by your operational runbook; do not do this casually).

> The workflow should not automatically delete the secret to “fix” drift.

---

## 8. Debug mode and artefacts (mandatory)

### 8.1 Toggle
- Workflow input `debug` (boolean) enables additional diagnostics and more verbose app logging.

### 8.2 Job separation
When `debug=true`, the workflow must include separate jobs such that artefacts are produced even if deployment fails.

Minimum job pattern:
- `deploy` (main job)
- `debug-artifacts` (separate job)
  - `needs: [deploy]`
  - `if: ${{ always() && inputs.debug }}`

### 8.3 Required debug artefacts
When debug is enabled, upload artefacts that are **safe** (no secrets):
- Rendered `values.generated.yaml` used for Helm
- `helm status`, `helm get values` (redacted values only)
- `kubectl get pods,svc,ingress,statefulset -o wide`
- `kubectl describe pod` for api server (best effort)
- `kubectl get events --sort-by=.lastTimestamp` (bounded output)
- api-server logs tail:
  - `kubectl logs ... --tail=200`
  - include `--previous` where relevant

**Explicitly forbidden:**
- Dumping Kubernetes Secrets
- Uploading env files containing passwords/keys
- Printing `WILDCARD_KEY`, `DEPLOY_SECRET`, `REGISTRY_PASSWORD`, `ALPINE_DATABASE_PASSWORD`, or `DTRACK_SECRET_KEY`

---

## 9. Authentication modes

### 9.1 Baseline (required): SP + client secret
- Workflow must support SP login reliably on self-hosted runners.

### 9.2 Advanced (optional): OIDC / Entra federation
- OIDC is an advanced option for future/hardened environments.
- Variables are staged and documented (optional), but baseline must not depend on them.

**Staged optional inputs (example contract):**
- `AZURE_AUTH_MODE` = `sp` (default) or `oidc`
- `AZURE_OIDC_CLIENT_ID` (var)
- plus tenant/subscription vars as normal

Implementation and rollout of this mode must not break baseline SP mode.

---

## 10. Compliance checklist

- [ ] Repo deploys Dependency-Track only (no Traefik changes)
- [ ] Helm/kubectl only in GitHub Actions; no TF helm/k8s providers
- [ ] Baseline Azure auth via SP + secret
- [ ] OIDC documented as advanced optional mode
- [ ] Registry uses `REGISTRY_*` only (Nexus-only)
- [ ] All sensitive values treated as secrets; no leakage to logs/artefacts
- [ ] Secret-key mastered in Key Vault; verify + fail on drift with remediation guidance
- [ ] Optional: Dependency-Track OIDC connector variables mapped and only written into the app-config secret when `DTRACK_OIDC_ENABLED=true`
- [ ] Debug is a boolean input; debug artefacts produced in separate job even if deploy fails
- [ ] Required GitHub Environment vars/secrets are documented with examples

---
