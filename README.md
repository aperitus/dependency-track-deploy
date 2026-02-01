# dependency-track-deploy (AKS via GHES)

Deploys **Dependency-Track** to an existing AKS cluster, using an existing **Traefik** ingress controller (managed in a separate repository).

## What this repo does

- Logs into Azure using **Service Principal + client secret** (no OIDC).
- Fetches AKS credentials and converts kubeconfig via **kubelogin**.
- Creates/updates:
  - Namespace: `dependency-track`
  - Image pull secret in `dependency-track`
  - TLS secret in `dependency-track` from wildcard cert/key
  - (Optional) application config secret for API server env vars (e.g., external DB)
- Renders a `values.generated.yaml` from a template **without printing secrets**.
- Installs/updates the official `dependencytrack/dependency-track` Helm chart with `--wait --atomic`.

## Environments

This repository expects GitHub **Environments** (e.g. `dev`, `prod`) with variables and secrets populated (typically by your Key Vault → GHES secret sync tool).

## Required variables and secrets

### Azure / AKS access

**Secrets** (preferred, but variables are supported via the resolver step):
- `DEPLOY_CLIENT_ID` – SP appId
- `DEPLOY_SECRET` – SP client secret
- `AZURE_TENANT_ID`
- `AZURE_SUBSCRIPTION_ID`

**Vars** (or secrets):
- `AKS_RESOURCE_GROUP`
- `AKS_CLUSTER_NAME`

### Nexus registry pull secret (for *all* images)

**Vars** (or secrets):
- `IMAGE_PULL_SECRET_NAME` (default: `nexus-pull`)
- `NEXUS_DOCKER_SERVER` (e.g. `docker-hosted-nexus.logiki.co.uk`)
- `NEXUS_DOCKER_USERNAME`

**Secrets**:
- `NEXUS_DOCKER_PASSWORD`

### Ingress TLS

**Vars** (or secrets):
- `INGRESS_TLS_SECRET_NAME` (default: `dtrack-wildcard-tls`)

**Secrets**:
- `WILDCARD_CRT` – PEM certificate (must include `-----BEGIN CERTIFICATE-----`)
- `WILDCARD_KEY` – PEM private key

### Dependency-Track chart and ingress settings

**Vars** (or secrets):
- `DTRACK_HELM_REPO_URL` (default: `https://dependencytrack.github.io/helm-charts`)
- `DTRACK_CHART_VERSION` (default: `0.41.0`)
- `DTRACK_RELEASE_NAME` (default: `dependency-track`)
- `DTRACK_NAMESPACE` (default: `dependency-track`)

**Vars**:
- `DTRACK_INGRESS_HOST` (default: `dtrack.logiki.co.uk`)
- `DTRACK_INGRESS_CLASS_NAME` (default: `traefik`)

### Image overrides (Nexus-only)

**Vars**:
- `DTRACK_IMAGE_REGISTRY` (default: value of `NEXUS_DOCKER_SERVER`)
- `DTRACK_APISERVER_IMAGE_REPOSITORY` (default: `dependencytrack/apiserver`)
- `DTRACK_FRONTEND_IMAGE_REPOSITORY` (default: `dependencytrack/frontend`)
- `DTRACK_APISERVER_IMAGE_TAG` (optional; default = chart appVersion)
- `DTRACK_FRONTEND_IMAGE_TAG` (optional; default = chart appVersion)

### Optional: API server extra env from secret

If you want the API server to use an external database, OIDC, etc., create a Kubernetes secret containing the required env vars.

**Vars**:
- `DTRACK_APP_CONFIG_SECRET_NAME` (default: `dependency-track-app-config`)

**Secrets/Vars** (examples; these are applied into the K8s secret if provided):
- `ALPINE_DATABASE_MODE` (set to `external`)
- `ALPINE_DATABASE_URL`
- `ALPINE_DATABASE_USERNAME`
- `ALPINE_DATABASE_PASSWORD`

> The workflow will only add keys that are set (var or secret). It will not echo values.

## Workflow

- `.github/workflows/deploy-dependency-track.yaml`

Run manually via **Actions → Deploy Dependency-Track**, selecting the environment.
