# dependency-track-deploy (AKS via GHES)

Deploys **Dependency-Track** to an existing AKS cluster, exposed via an existing **Traefik** ingress controller (Traefik is managed in a separate repository and is treated as the source of truth).

## What this repo does

- Logs into Azure using **Service Principal + client secret** (no OIDC).
- Fetches AKS credentials and converts kubeconfig via **kubelogin** (SPN login mode).
- Creates/updates in namespace `dependency-track`:
  - Image pull secret (REGISTRY_* – Nexus Docker registry)
  - TLS secret from `WILDCARD_CRT` / `WILDCARD_KEY`
  - Application config secret for API server environment variables (includes external Postgres JDBC URL)
- Renders `values.generated.yaml` from a template **without writing secret material to logs**.
- Installs/updates the official `dependencytrack/dependency-track` Helm chart using `--wait --atomic --timeout`.

## Environments

This repository expects GitHub **Environments** (e.g. `dev`, `preprod`, `prod`) with variables and secrets populated (typically by your Key Vault → GHES secret sync tool).

The workflow resolves each key using a **vars-first fallback**:

- If `vars.<KEY>` is non-empty, it is used.
- Otherwise `secrets.<KEY>` is used.

## Persisting the Dependency-Track secret key

Dependency-Track uses a **stable application secret key** for crypto (tokens, etc.). If this key changes between deployments, existing encrypted material can become unusable.

Recommended practice is to **master the key in Key Vault** (as a GitHub Environment Secret via your secret-sync tool) and have this repo **create/verify** the Kubernetes secret on deploy.

### New deployment (recommended)

1. Generate 32 bytes of random key material and base64 encode it (single line):

   ```bash
   openssl rand 32 | base64 -w 0
   ```

2. Store the base64 output in Key Vault as a secret whose name maps to `DTRACK_SECRET_KEY`, e.g.:

   - Key Vault secret name: `auto--dependency-track-deploy--dtrack-secret-key`
   - Tag: *none* (this is sensitive, so it should sync as a GitHub **secret**)

3. Set/leave `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` (optional). If unset, the workflow defaults to `dtrack-secret-key` when `DTRACK_SECRET_KEY` is provided.

4. Run the workflow. It will create the Kubernetes secret if missing, and then configure Helm to use it.

### Existing deployment (avoid rotation)

If a secret key secret already exists in the cluster, do **not** generate a new one. Instead, export the current base64 value and store that in Key Vault:

```bash
kubectl -n dependency-track get secret dtrack-secret-key -o jsonpath='{.data.secret\.key}'
```

Store the returned base64 string in Key Vault (same name as above), let it sync to GitHub, then re-run the deploy.

The workflow will **fail** if the in-cluster secret and `DTRACK_SECRET_KEY` differ. This is intentional to prevent accidental crypto key rotation.
## Workflow inputs (Actions → Run workflow)

| Input | Required | Description | Example |
|---|---:|---|---|
| `environment` | Yes | GitHub Environment to use for variables/secrets. | `dev` |
| `use_admin_credentials` | No | If `true`, uses AKS **admin** kubeconfig (`az aks get-credentials --admin`). | `false` |
| `helm_timeout` | No | Helm timeout. If numeric, treated as minutes; otherwise must include unit suffix (`s`, `m`, `h`). | `15m` or `10` |
| `dtrack_debug` | No | If `true`, sets `LOGGING_LEVEL=DEBUG` for the API server and prints additional diagnostics steps. | `true` |

### Environment keys (vars/secrets)

When `dtrack_debug` is enabled, the workflow appends `LOGGING_LEVEL=DEBUG` to the API server app-config secret. Dependency-Track supports setting `LOGGING_LEVEL` to `DEBUG`/`TRACE` in Docker deployments for more verbose logs.

**Guidance:** store sensitive values as **Environment Secrets** (recommended). Non-sensitive values can be Environment Variables.

| Key | Suggested storage | Required | Description | Example |
|---|---|---:|---|---|
| `DEPLOY_CLIENT_ID` | Var (or Secret) | Yes | Azure Service Principal **appId** used by GitHub Actions. | `00000000-0000-0000-0000-000000000000` |
| `DEPLOY_SECRET` | Secret | Yes | Azure Service Principal client secret for `DEPLOY_CLIENT_ID`. | *(secret value)* |
| `AZURE_TENANT_ID` | Var (or Secret) | Yes | Azure tenant GUID. | `11111111-1111-1111-1111-111111111111` |
| `AZURE_SUBSCRIPTION_ID` | Var (or Secret) | Yes | Azure subscription GUID containing the AKS cluster. | `22222222-2222-2222-2222-222222222222` |
| `AKS_RESOURCE_GROUP` | Var (or Secret) | Yes | Resource group name that contains the AKS cluster. | `rg-aks-uksouth-01` |
| `AKS_CLUSTER_NAME` | Var (or Secret) | Yes | AKS cluster name. | `aks-uksouth-01` |
| `REGISTRY_SERVER` | Var (or Secret) | Yes | Docker registry host (Nexus). Used for pull secret and as the image registry for all Dependency-Track images. | `docker-hosted-nexus.logiki.co.uk` |
| `REGISTRY_USERNAME` | Var (or Secret) | Yes | Docker registry username for pulls (Nexus). | `svc-docker-pull` |
| `REGISTRY_PASSWORD` | Secret | Yes | Docker registry password for pulls (Nexus). | *(secret value)* |
| `IMAGE_PULL_SECRET_NAME` | Var (or Secret) | No | Name of the `kubernetes.io/dockerconfigjson` secret created in `dependency-track`. Default: `nexus-pull`. | `nexus-pull` |
| `WILDCARD_CRT` | Secret | Yes | Wildcard TLS certificate (PEM). Must contain `-----BEGIN CERTIFICATE-----`. | `-----BEGIN CERTIFICATE-----\n...` |
| `WILDCARD_KEY` | Secret | Yes | Wildcard TLS private key (PEM). Must contain `-----BEGIN PRIVATE KEY-----` (or RSA variant). | `-----BEGIN PRIVATE KEY-----\n...` |
| `INGRESS_TLS_SECRET_NAME` | Var (or Secret) | No | Name of the `kubernetes.io/tls` secret created in `dependency-track`. Default: `dtrack-wildcard-tls`. | `dtrack-wildcard-tls` |
| `ALPINE_DATABASE_MODE` | Var (or Secret) | No | Database mode for Dependency-Track. For external Postgres use `external`. Default: `external`. | `external` |
| `ALPINE_DATABASE_URL` | Var (or Secret) | Yes | Database URL. Preferred format is JDBC: `jdbc:postgresql://host:5432/db?sslmode=require`. A libpq URL (`postgres://...`) is accepted and will be converted to JDBC at runtime. | `jdbc:postgresql://psql-dtrack-01.privatelink.postgres.database.azure.com:5432/dtrack?sslmode=require` |
| `ALPINE_DATABASE_USERNAME` | Var (or Secret) | Yes | Database username for the Dependency-Track backend. | `dtrack_app` |
| `ALPINE_DATABASE_PASSWORD` | Secret | Yes | Database password for the Dependency-Track backend. | *(secret value)* |
| `DTRACK_DB_URL` | Secret (or Var) | No | Legacy compatibility key. Used only if `ALPINE_DATABASE_URL` is empty. Must be JDBC (`jdbc:postgresql://...`) or libpq (`postgres://...`). | `jdbc:postgresql://...` |
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
| `DTRACK_FRONTEND_API_BASE_URL` | Var (or Secret) | No | Optional override for frontend API base URL (rare; only if your frontend must point at a non-standard API URL). | `https://dtrack.logiki.co.uk/api` |
| `DTRACK_SECRET_KEY_CREATE` | Var (or Secret) | No | If `true`, the Helm chart will generate and manage a secret key in-cluster. Default: `true`. If you set `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` (or provide `DTRACK_SECRET_KEY`), this flag is forced to `false`. | `true` |
| `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` | Var (or Secret) | No | If set, use this K8s secret name for the secret key. If it does not exist, the workflow creates it once (and will not overwrite it on future runs). | `dtrack-secret-key` |
| `DTRACK_SECRET_KEY` | Secret | No | Base64-encoded secret-key material (at least 32 bytes). If set, the workflow creates/verifies the Kubernetes secret (and refuses rotation if it mismatches). Recommended to master this in Key Vault for migration. | `b64...` |
| `DTRACK_INGRESS_ANNOTATIONS_JSON` | Var (or Secret) | No | JSON object of annotations to apply to the Ingress. Must be valid JSON object. Default: `{}`. | `{ "traefik.ingress.kubernetes.io/router.entrypoints": "websecure" }` |
| `DTRACK_APISERVER_PV_ENABLED` | Var (or Secret) | No | Placeholder for PV enablement (chart-dependent). Default: `false`. | `false` |
| `DTRACK_APISERVER_PV_CLASSNAME` | Var (or Secret) | No | Placeholder for storageClassName if PV enabled. | `managed-csi` |
| `DTRACK_APISERVER_PV_SIZE` | Var (or Secret) | No | Placeholder size if PV enabled. Default: `5Gi`. | `5Gi` |

## Workflow

- `.github/workflows/deploy-dependency-track.yaml`

Run manually via **Actions → Deploy Dependency-Track**, selecting the environment.

Notes:
- The job echoes a subset of resolved inputs early for debugging. If a value is sourced from GitHub secrets, it should appear masked in logs.
- TLS PEM values (`WILDCARD_CRT` / `WILDCARD_KEY`) and passwords are never echoed.
