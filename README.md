# dependency-track-deploy (AKS via GHES)

Deploys **Dependency-Track** to an existing AKS cluster, exposed via an existing **Traefik** ingress controller (Traefik is managed in a separate repository and is treated as the source of truth).

## What this repo does

- Logs into Azure using **Service Principal + client secret** (no OIDC).
- Fetches AKS credentials and converts kubeconfig via **kubelogin** (SPN login mode).
- Creates/updates in namespace `dependency-track`:
  - Image pull secret (Nexus Docker registry)
  - TLS secret from `WILDCARD_CRT` / `WILDCARD_KEY`
  - Application config secret for API server environment variables (includes external Postgres JDBC URL)
- Renders `values.generated.yaml` from a template **without writing secret material to logs**.
- Installs/updates the official `dependencytrack/dependency-track` Helm chart using `--wait --atomic --timeout`.

## Environments

This repository expects GitHub **Environments** (e.g. `dev`, `preprod`, `prod`) with variables and secrets populated (typically by your Key Vault → GHES secret sync tool).

The workflow resolves each key using a **vars-first fallback**:

- If `vars.<KEY>` is non-empty, it is used.
- Otherwise `secrets.<KEY>` is used.

## Configuration reference

### Workflow inputs (Actions → Run workflow)

| Input | Required | Description | Example |
|---|---:|---|---|
| `environment` | Yes | GitHub Environment to use for variables/secrets. | `dev` |
| `use_admin_credentials` | No | If `true`, uses AKS **admin** kubeconfig (`az aks get-credentials --admin`). | `false` |
| `helm_timeout` | No | Helm timeout. If numeric, treated as minutes; otherwise must include unit suffix (`s`, `m`, `h`). | `15m` or `10` |

### Environment keys (vars/secrets)

**Guidance:** store sensitive values as **Environment Secrets** (recommended). Non-sensitive values can be Environment Variables.

| Key | Suggested storage | Required | Description | Example |
|---|---|---:|---|---|
| `DEPLOY_CLIENT_ID` | Var (or Secret) | Yes | Azure Service Principal **appId** used by GitHub Actions. | `00000000-0000-0000-0000-000000000000` |
| `DEPLOY_SECRET` | Secret | Yes | Azure Service Principal client secret for `DEPLOY_CLIENT_ID`. | *(secret value)* |
| `AZURE_TENANT_ID` | Var (or Secret) | Yes | Azure tenant GUID. | `11111111-1111-1111-1111-111111111111` |
| `AZURE_SUBSCRIPTION_ID` | Var (or Secret) | Yes | Azure subscription GUID containing the AKS cluster. | `22222222-2222-2222-2222-222222222222` |
| `AKS_RESOURCE_GROUP` | Var (or Secret) | Yes | Resource group name that contains the AKS cluster. | `rg-aks-uksouth-01` |
| `AKS_CLUSTER_NAME` | Var (or Secret) | Yes | AKS cluster name. | `aks-uksouth-01` |
| `NEXUS_DOCKER_SERVER` | Var (or Secret) | Yes | Nexus Docker registry host (used for pull secret; also used as default image registry). | `docker-hosted-nexus.logiki.co.uk` |
| `NEXUS_DOCKER_USERNAME` | Var (or Secret) | Yes | Nexus Docker registry username for pulls. | `svc-docker-pull` |
| `NEXUS_DOCKER_PASSWORD` | Secret | Yes | Nexus Docker registry password for pulls. | *(secret value)* |
| `IMAGE_PULL_SECRET_NAME` | Var (or Secret) | No | Name of the `kubernetes.io/dockerconfigjson` secret created in `dependency-track`. Default: `nexus-pull`. | `nexus-pull` |
| `WILDCARD_CRT` | Secret | Yes | Wildcard TLS certificate (PEM). Must contain `-----BEGIN CERTIFICATE-----`. | `-----BEGIN CERTIFICATE-----\n...` |
| `WILDCARD_KEY` | Secret | Yes | Wildcard TLS private key (PEM). Must contain `-----BEGIN PRIVATE KEY-----` (or RSA variant). | `-----BEGIN PRIVATE KEY-----\n...` |
| `INGRESS_TLS_SECRET_NAME` | Var (or Secret) | No | Name of the `kubernetes.io/tls` secret created in `dependency-track`. Default: `dtrack-wildcard-tls`. | `dtrack-wildcard-tls` |
| `DTRACK_DB_URL` | Secret (or Var) | Yes | Postgres JDBC URL consumed by Dependency-Track (mapped to `ALPINE_DATABASE_URL`). | `jdbc:postgresql://myserver.postgres.database.azure.com:5432/dependencytrack?sslmode=require` |
| `DTRACK_NAMESPACE` | Var (or Secret) | No | Kubernetes namespace for the release. Default: `dependency-track`. | `dependency-track` |
| `DTRACK_RELEASE_NAME` | Var (or Secret) | No | Helm release name. Default: `dependency-track`. | `dependency-track` |
| `DTRACK_INGRESS_HOST` | Var (or Secret) | No | Public hostname for the app ingress. Default: `dtrack.logiki.co.uk`. | `dtrack.logiki.co.uk` |
| `DTRACK_INGRESS_CLASS_NAME` | Var (or Secret) | No | IngressClass name used by Traefik. Default: `traefik`. | `traefik` |
| `DTRACK_HELM_REPO_URL` | Var (or Secret) | No | Helm repository URL hosting the Dependency-Track chart. Default: `https://dependencytrack.github.io/helm-charts`. | `https://dependencytrack.github.io/helm-charts` |
| `DTRACK_CHART_VERSION` | Var (or Secret) | No | Pinned chart version. Default: `0.41.0`. | `0.41.0` |
| `DTRACK_APP_CONFIG_SECRET_NAME` | Var (or Secret) | No | Name of the K8s secret created for API server env vars. Default: `dependency-track-app-config`. | `dependency-track-app-config` |
| `DTRACK_IMAGE_REGISTRY` | Var (or Secret) | No | Registry host for Dependency-Track images. Default: `NEXUS_DOCKER_SERVER`. | `docker-hosted-nexus.logiki.co.uk` |
| `DTRACK_APISERVER_IMAGE_REPOSITORY` | Var (or Secret) | No | Repository path for apiserver image (relative to registry). Default: `dependencytrack/apiserver`. | `dependencytrack/apiserver` |
| `DTRACK_FRONTEND_IMAGE_REPOSITORY` | Var (or Secret) | No | Repository path for frontend image (relative to registry). Default: `dependencytrack/frontend`. | `dependencytrack/frontend` |
| `DTRACK_APISERVER_IMAGE_REGISTRY` | Var (or Secret) | No | Optional per-component override for apiserver registry. Empty means use `DTRACK_IMAGE_REGISTRY`. | `docker-hosted-nexus.logiki.co.uk` |
| `DTRACK_FRONTEND_IMAGE_REGISTRY` | Var (or Secret) | No | Optional per-component override for frontend registry. Empty means use `DTRACK_IMAGE_REGISTRY`. | `docker-hosted-nexus.logiki.co.uk` |
| `DTRACK_APISERVER_IMAGE_TAG` | Var (or Secret) | No | Optional apiserver image tag override. Empty means chart default (usually appVersion). | `4.11.0` |
| `DTRACK_FRONTEND_IMAGE_TAG` | Var (or Secret) | No | Optional frontend image tag override. Empty means chart default (usually appVersion). | `4.11.0` |
| `DTRACK_FRONTEND_API_BASE_URL` | Var (or Secret) | No | Optional override for frontend API base URL (if you need a non-default routing). | `https://dtrack.logiki.co.uk/api` |
| `DTRACK_SECRET_KEY_CREATE` | Var (or Secret) | No | If `true`, workflow generates a random secret key and stores it in a K8s secret. Default: `true`. | `true` |
| `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` | Var (or Secret) | No | If set, uses an existing K8s secret containing the secret key instead of generating one. | `dtrack-secret-key` |
| `DTRACK_INGRESS_ANNOTATIONS_JSON` | Var (or Secret) | No | JSON object of annotations to apply to the Ingress. Must be valid JSON object. Default: `{}`. | `{ "traefik.ingress.kubernetes.io/router.entrypoints": "websecure" }` |
| `ALPINE_DATABASE_MODE` | Var (or Secret) | No | Advanced override; if set, written into app config secret. If unset, workflow uses `external`. | `external` |
| `ALPINE_DATABASE_URL` | Var (or Secret) | No | Advanced override; if set, overrides `DTRACK_DB_URL` mapping. | `jdbc:postgresql://...` |
| `ALPINE_DATABASE_USERNAME` | Secret (or Var) | No | Advanced override; DB username if needed by your setup. | `dtrackuser` |
| `ALPINE_DATABASE_PASSWORD` | Secret | No | Advanced override; DB password if needed by your setup. | *(secret value)* |
| `DTRACK_APISERVER_PV_ENABLED` | Var (or Secret) | No | Placeholder for PV enablement (chart-dependent). Default: `false`. | `false` |
| `DTRACK_APISERVER_PV_CLASSNAME` | Var (or Secret) | No | Placeholder for storageClassName if PV enabled. | `managed-csi` |
| `DTRACK_APISERVER_PV_SIZE` | Var (or Secret) | No | Placeholder size if PV enabled. Default: `5Gi`. | `5Gi` |

## Workflow

- `.github/workflows/deploy-dependency-track.yaml`

Run manually via **Actions → Deploy Dependency-Track**, selecting the environment.

Notes:
- The job echoes a subset of resolved inputs early for debugging. If a value is sourced from GitHub secrets, it should appear masked in logs.
- TLS PEM values (`WILDCARD_CRT` / `WILDCARD_KEY`) and passwords are never echoed.
