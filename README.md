# dependency-track-deploy (AKS via GHES)

Deploys **Dependency-Track** to an existing AKS cluster, exposed via an existing **Traefik** ingress controller (Traefik is managed in a separate repository and is treated as the source of truth).

For the definitive contract, see: **Dependency-Track Deploy — Authoritative Design & Compliance**.

- `Dependency-Track Deploy — Authoritative Design & Compliance.md`

## What this repo does

- Logs into Azure using **Service Principal + client secret** (baseline).
  - OIDC / Entra federation is staged as an **advanced option** and documented as optional.
- Fetches AKS credentials and converts kubeconfig via **kubelogin** (SPN login mode).
- Creates/updates in namespace `dependency-track`:
  - Image pull secret (REGISTRY_* – Nexus Docker registry)
  - TLS secret from `WILDCARD_CRT` / `WILDCARD_KEY`
  - **Secret key secret** for Dependency-Track crypto (mastered externally; drift-checked)
  - Application config secret for API server environment variables (includes external Postgres JDBC URL)
- Renders `values.generated.yaml` from a template **without writing secret material to logs**.
- Installs/updates the official `dependencytrack/dependency-track` Helm chart using `--wait --atomic --timeout`.

## Environments

This repository expects GitHub **Environments** (e.g. `dev`, `preprod`, `prod`) with variables and secrets populated (typically by your Key Vault → GHES secret sync tool).

The workflow resolves each key using a **vars-first fallback**:

- If `vars.<KEY>` is non-empty, it is used.
- Otherwise `secrets.<KEY>` is used.

## Persisting the Dependency-Track secret key (mandatory)

Dependency-Track uses a **stable application secret key** for crypto (tokens, encryption). If this key changes between deployments, existing encrypted material can become unusable.

**Standard practice:** master the key in **Key Vault**, sync it as a GitHub **Environment Secret** named `DTRACK_SECRET_KEY`, and have this repo **create/verify** the Kubernetes secret on deploy.

### New deployment

1. Generate 32 bytes and base64 encode (single line):

   ```bash
   openssl rand 32 | base64 -w 0
   ```

2. Store that base64 string in Key Vault so it syncs to GitHub Environment secret `DTRACK_SECRET_KEY`.
3. Run the workflow. It will create the Kubernetes secret (if missing) and configure the chart to use it.

### Existing deployment (avoid rotation)

If a secret key already exists in the cluster, do **not** generate a new one. Export the current base64 value and master that:

```bash
kubectl -n dependency-track get secret dtrack-secret-key -o jsonpath='{.data.secret\.key}'
```

Store the returned base64 string in Key Vault → let it sync → re-run the deploy.

### Drift enforcement

The workflow **fails** if the in-cluster secret and `DTRACK_SECRET_KEY` differ. This is intentional to prevent accidental crypto key rotation.

Remediation is printed in the workflow logs and includes:

- Align mastering to runtime (recommended): export cluster value and set it into Key Vault.
- Forced rotation (destructive): delete the Kubernetes secret and redeploy only if you understand impact.

## Workflow inputs (Actions → Run workflow)

| Input | Required | Description | Example |
|---|---:|---|---|
| `environment` | Yes | GitHub Environment to use for variables/secrets. | `dev` |
| `debug` | No | If `true`, enables `LOGGING_LEVEL=DEBUG` and runs a separate debug artefacts job (runs even if deploy fails). | `true` |
| `use_admin_credentials` | No | If `true`, uses AKS **admin** kubeconfig (`az aks get-credentials --admin`). | `false` |
| `helm_timeout` | No | Helm timeout. Must include unit suffix (`s`, `m`, `h`) or be a number (minutes). | `15m` or `10` |

## Environment keys (vars/secrets)

**Guidance:** store sensitive values as **Environment Secrets** (recommended). Non-sensitive values can be Environment Variables.

> This repo consumes keys only. Secret sync and mastering is handled externally.

| Key | Suggested storage | Required | Description | Example |
|---|---|---:|---|---|
| `DEPLOY_CLIENT_ID` | Var (or Secret) | Yes | Azure Service Principal **appId** used by GitHub Actions. | `00000000-0000-0000-0000-000000000000` |
| `DEPLOY_SECRET` | Secret | Yes | Azure Service Principal client secret for `DEPLOY_CLIENT_ID`. | *(secret value)* |
| `AZURE_TENANT_ID` | Var (or Secret) | Yes | Azure tenant GUID. | `11111111-1111-1111-1111-111111111111` |
| `AZURE_SUBSCRIPTION_ID` | Var (or Secret) | Yes | Azure subscription GUID containing the AKS cluster. | `22222222-2222-2222-2222-222222222222` |
| `AKS_RESOURCE_GROUP` | Var (or Secret) | Yes | Resource group name that contains the AKS cluster. | `rg-aks-uksouth-01` |
| `AKS_CLUSTER_NAME` | Var (or Secret) | Yes | AKS cluster name. | `aks-uksouth-01` |
| `REGISTRY_SERVER` | Var (or Secret) | Yes | Docker registry host (Nexus). Used for pull secret and as the image registry for Dependency-Track images. | `docker-group-nexus.logiki.co.uk` |
| `REGISTRY_USERNAME` | Var (or Secret) | Yes | Docker registry username for pulls (Nexus). | `svc-docker-pull` |
| `REGISTRY_PASSWORD` | Secret | Yes | Docker registry password for pulls (Nexus). | *(secret value)* |
| `IMAGE_PULL_SECRET_NAME` | Var (or Secret) | No | Name of the `kubernetes.io/dockerconfigjson` secret created in `dependency-track`. Default: `nexus-pull`. | `nexus-pull` |
| `WILDCARD_CRT` | Secret | Yes | Wildcard TLS certificate (PEM). Must contain `-----BEGIN CERTIFICATE-----`. | `-----BEGIN CERTIFICATE-----\n...` |
| `WILDCARD_KEY` | Secret | Yes | Wildcard TLS private key (PEM). Must contain `-----BEGIN PRIVATE KEY-----` (or RSA variant). | `-----BEGIN PRIVATE KEY-----\n...` |
| `INGRESS_TLS_SECRET_NAME` | Var (or Secret) | No | Name of the `kubernetes.io/tls` secret created in `dependency-track`. Default: `dtrack-wildcard-tls`. | `dtrack-wildcard-tls` |
| `ALPINE_DATABASE_MODE` | Var (or Secret) | No | Database mode for Dependency-Track. For external Postgres use `external`. Default: `external`. | `external` |
| `ALPINE_DATABASE_URL` | Var (or Secret) | Yes | JDBC URL (must start with `jdbc:postgresql://`). | `jdbc:postgresql://psql-dtrack-01.privatelink.postgres.database.azure.com:5432/dtrack?sslmode=require` |
| `ALPINE_DATABASE_USERNAME` | Var (or Secret) | Yes | DB username for the Dependency-Track backend. | `dtrack_app` |
| `ALPINE_DATABASE_PASSWORD` | Secret | Yes | DB password for the Dependency-Track backend. | *(secret value)* |
| `DTRACK_SECRET_KEY` | Secret | Yes | Base64-encoded secret-key material (>= 32 bytes). Master in Key Vault for migration. | `b64...` |
| `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` | Var (or Secret) | No | Name of the Kubernetes Secret that holds the secret key. Default: `dtrack-secret-key`. | `dtrack-secret-key` |
| `DTRACK_NAMESPACE` | Var (or Secret) | No | Kubernetes namespace for the release. Default: `dependency-track`. | `dependency-track` |
| `DTRACK_RELEASE_NAME` | Var (or Secret) | No | Helm release name. Default: `dependency-track`. | `dependency-track` |
| `DTRACK_INGRESS_HOST` | Var (or Secret) | No | Public hostname for the app ingress. Default: `dtrack.logiki.co.uk`. | `dtrack.logiki.co.uk` |
| `DTRACK_INGRESS_CLASS_NAME` | Var (or Secret) | No | IngressClass name used by Traefik. Default: `traefik`. | `traefik` |
| `DTRACK_HELM_REPO_URL` | Var (or Secret) | No | Helm repository URL hosting the Dependency-Track chart. Default: `https://dependencytrack.github.io/helm-charts`. | `https://dependencytrack.github.io/helm-charts` |
| `DTRACK_CHART_VERSION` | Var (or Secret) | No | Pinned chart version. Default: `0.41.0`. | `0.41.0` |
| `DTRACK_APP_CONFIG_SECRET_NAME` | Var (or Secret) | No | Name of the K8s secret created for API server env vars. Default: `dependency-track-app-config`. | `dependency-track-app-config` |
| `DTRACK_APISERVER_IMAGE_REPOSITORY` | Var (or Secret) | No | Repository path for apiserver image (relative to registry). Default: `dependencytrack/apiserver`. | `dependencytrack/apiserver` |
| `DTRACK_FRONTEND_IMAGE_REPOSITORY` | Var (or Secret) | No | Repository path for frontend image (relative to registry). Default: `dependencytrack/frontend`. | `dependencytrack/frontend` |
| `DTRACK_APISERVER_IMAGE_TAG` | Var (or Secret) | No | Optional apiserver image tag override. Empty means chart default (usually appVersion). | `4.11.0` |
| `DTRACK_FRONTEND_IMAGE_TAG` | Var (or Secret) | No | Optional frontend image tag override. Empty means chart default (usually appVersion). | `4.11.0` |
| `DTRACK_FRONTEND_API_BASE_URL` | Var (or Secret) | No | Optional override for frontend API base URL. | `https://dtrack.logiki.co.uk/api` |
| `DTRACK_INGRESS_ANNOTATIONS_JSON` | Var (or Secret) | No | JSON object of annotations to apply to the Ingress. Default: `{}`. | `{ "traefik.ingress.kubernetes.io/router.entrypoints": "websecure" }` |
| `DTRACK_APISERVER_PV_ENABLED` | Var (or Secret) | No | Placeholder for PV enablement (chart-dependent). Default: `false`. | `false` |
| `DTRACK_APISERVER_PV_CLASSNAME` | Var (or Secret) | No | Placeholder for storageClassName if PV enabled. | `managed-csi` |
| `DTRACK_APISERVER_PV_SIZE` | Var (or Secret) | No | Placeholder size if PV enabled. Default: `5Gi`. | `5Gi` |

### Advanced (staged) – OIDC / Entra federation

This repo is baseline SP-secret. For future hardening, you may stage variables for OIDC, for example:

- `AZURE_AUTH_MODE` = `oidc`
- `AZURE_OIDC_CLIENT_ID` = (federated app client id)

Implementation is intentionally out of scope for the baseline workflow.

## Workflow

- `.github/workflows/deploy-dependency-track.yaml`

Run manually via **Actions → Deploy Dependency-Track**, selecting the environment.

Notes:
- TLS PEM values (`WILDCARD_CRT` / `WILDCARD_KEY`) and passwords are never echoed.
- When `debug=true`, a separate job uploads debug artefacts (including `values.generated.yaml`).
