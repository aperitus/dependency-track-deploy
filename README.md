# dependency-track-deploy

Deploy **OWASP Dependency-Track** to AKS using **GitHub Actions** on **GitHub Enterprise Server (GHES)**.

This repository **does not** deploy Traefik. It assumes the **Traefik baseline ingress repo** (your `traefik-aks-ingress` repo) is already installed and operating in `routing_mode=ingress` or `both`.

## Target

- Namespace: `dependency-track`
- Release name: `dependency-track`
- Ingress host: `dtrack.logiki.co.uk`
- Ingress class: `traefik` (Kubernetes Ingress compatibility mode)

## Key behaviours

- Idempotent: safe to re-run.
- Auth to Azure using **Service Principal + client secret** (no OIDC federation).
- Images pulled from **Nexus** (registry override via chart values) and a namespace imagePullSecret.
- TLS secret created/updated in the **app namespace**.
- Sensitive app config is stored in a Kubernetes Secret (`dependency-track-app-config`) and referenced via `apiServer.extraEnvFrom`.
- Helm uses pinned chart version and `--wait --atomic --timeout`.

## Workflow

The main workflow is:

- `.github/workflows/deploy-dependency-track.yaml`

It performs:

1. Resolve inputs (prefer **Environment variables** `vars.<NAME>` then **Environment secrets** `secrets.<NAME>`).
2. Azure login + AKS kubeconfig.
3. Ensure namespace exists.
4. Create/update:
   - `IMAGE_PULL_SECRET_NAME` (dockerconfigjson) in `dependency-track`
   - `INGRESS_TLS_SECRET_NAME` (TLS) in `dependency-track`
   - `dependency-track-app-config` (generic secret) in `dependency-track`
5. Render a minimal `values.generated.yaml` (no secret values).
6. `helm upgrade --install` the official chart.
7. Basic post-deploy checks.

## Required GitHub Environment configuration

Create a GitHub **Environment** (e.g. `prod`) and populate the following. You may place non-sensitive items as **vars** and sensitive items as **secrets**.

> Input resolution order: `vars.<NAME>` then `secrets.<NAME>`.

### Azure / AKS

- `DEPLOY_CLIENT_ID` (App registration / SP client ID) (var recommended)
- `DEPLOY_TENANT_ID` (var recommended)
- `DEPLOY_SUBSCRIPTION_ID` (var recommended)
- `DEPLOY_SECRET` (secret)
- `AKS_RESOURCE_GROUP` (var recommended)
- `AKS_CLUSTER_NAME` (var recommended)

### Nexus registry

- `NEXUS_DOCKER_REGISTRY` (e.g. `docker-hosted-nexus.logiki.co.uk`) (var recommended)
- `NEXUS_DOCKER_USERNAME` (secret)
- `NEXUS_DOCKER_PASSWORD` (secret)
- `IMAGE_PULL_SECRET_NAME` (e.g. `nexus-docker-creds`) (var recommended)

### TLS for Ingress

- `INGRESS_TLS_SECRET_NAME` (e.g. `wildcard-tls`) (var recommended)
- `WILDCARD_CRT` (secret) — PEM certificate (`-----BEGIN CERTIFICATE-----`)
- `WILDCARD_KEY` (secret) — PEM private key (`-----BEGIN PRIVATE KEY-----`)

### Dependency-Track application

- `DTRACK_DB_URL` (secret) — JDBC URL for external DB.
  - Example: `jdbc:postgresql://postgres.example.internal:5432/dtrack?user=dtrack&password=...`
- Optional: `DTRACK_EXTRA_ENV_YAML` (secret) — additional env entries as YAML list items (advanced; see workflow comments).

### Helm / chart

- `DTRACK_HELM_REPO_URL` (var) — default: `https://dependencytrack.github.io/helm-charts`
- `DTRACK_CHART_VERSION` (var) — default: `0.41.0`
- `DTRACK_INGRESS_HOST` (var) — default: `dtrack.logiki.co.uk`
- `HELM_TIMEOUT` (var) — default: `15m`

## Notes

- The Dependency-Track chart values schema used here comes from the official chart (`dependency-track/dependency-track`).
- Traefik’s ingress onboarding guidance expects `spec.ingressClassName: traefik` and a TLS secret in the same namespace as the Ingress.

