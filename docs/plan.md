# Deployment plan — dependency-track-deploy

## Objective

Deploy **Dependency-Track** into AKS namespace `dependency-track` using a GHES GitHub Actions workflow, and expose it through the **Traefik** ingress baseline using a Kubernetes `Ingress` (compatibility mode).

## Dependency graph

1) **Traefik baseline repo** (source of truth: `traefik-aks-ingress-v1.0.7.zip`)
   - Installs Traefik in the cluster and configures routing (Ingress / Gateway API).
   - Expects app repos to create their own TLS secret in their own namespace.

2) **This repo** (`dependency-track-deploy`)
   - Creates namespace-scoped secrets and deploys the official Helm chart.

## Work breakdown

### A. GitHub Environment configuration

Create an Environment (e.g. `prod`) and populate the following keys. Non-sensitive items may be `vars`; sensitive should be `secrets`.

Resolution order: `vars.<NAME>` → `secrets.<NAME>`.

| Key | Type | Required | Purpose |
|---|---:|---:|---|
| `DEPLOY_CLIENT_ID` | var/secret | yes | Azure SP client ID (appId). |
| `DEPLOY_TENANT_ID` | var/secret | yes | Azure tenant ID. |
| `DEPLOY_SUBSCRIPTION_ID` | var/secret | yes | Subscription containing the AKS cluster. |
| `DEPLOY_SECRET` | secret | yes | Azure SP client secret. |
| `AKS_RESOURCE_GROUP` | var/secret | yes | AKS RG name. |
| `AKS_CLUSTER_NAME` | var/secret | yes | AKS cluster name. |
| `NEXUS_DOCKER_REGISTRY` | var/secret | yes | Nexus registry host (e.g. `docker-hosted-nexus.logiki.co.uk`). |
| `NEXUS_DOCKER_USERNAME` | secret | yes | Nexus basic auth username. |
| `NEXUS_DOCKER_PASSWORD` | secret | yes | Nexus basic auth password. |
| `IMAGE_PULL_SECRET_NAME` | var/secret | yes | K8s imagePullSecret name to create/update in `dependency-track`. |
| `INGRESS_TLS_SECRET_NAME` | var/secret | yes | K8s TLS Secret name used by the Ingress in `dependency-track`. |
| `WILDCARD_CRT` | secret | yes | Wildcard certificate PEM. |
| `WILDCARD_KEY` | secret | yes | Wildcard private key PEM. |
| `DTRACK_DB_URL` | secret | yes | JDBC URL for external Postgres (stored into `dependency-track-app-config`). |
| `DTRACK_INGRESS_HOST` | var/secret | no | Hostname. Default: `dtrack.logiki.co.uk`. |
| `DTRACK_HELM_REPO_URL` | var/secret | no | Chart repo. Default: `https://dependencytrack.github.io/helm-charts`. |
| `DTRACK_CHART_VERSION` | var/secret | no | Chart version pin. Default: `0.41.0`. |
| `DTRACK_IMAGE_TAG` | var/secret | no | Optional image tag override (blank uses chart AppVersion). |
| `HELM_TIMEOUT` | var/secret | no | Helm timeout. Default: `15m`. |

### B. AKS prerequisites

- The Service Principal must have rights to obtain cluster credentials and create/update objects in the target namespace.
  Typical minimal model:
  - Azure RBAC: `Azure Kubernetes Service Cluster User Role` on the AKS resource (or equivalent).
  - Kubernetes RBAC: access to `dependency-track` namespace (or cluster-admin during bootstrap).

### C. Workflow execution

Run `.github/workflows/deploy-dependency-track.yaml` in the target Environment.

The workflow will:

1. Resolve inputs (vars → secrets), logging source selection (secrets redacted).
2. Login to Azure with SP.
3. Pull kubeconfig for AKS.
4. Create/update:
   - Namespace `dependency-track`
   - Image pull secret `${IMAGE_PULL_SECRET_NAME}`
   - TLS secret `${INGRESS_TLS_SECRET_NAME}`
   - App config secret `dependency-track-app-config`
5. Generate `values.generated.yaml` (no secret values) with:
   - Nexus registry override
   - Traefik ingress enabled (`ingressClassName: traefik`)
   - `apiServer.extraEnvFrom` referencing `dependency-track-app-config`
6. Deploy chart with `--wait --atomic --timeout`.
7. Dump basic resources for validation.

## Validation

- `kubectl -n dependency-track get ingress` should show an Ingress with:
  - `spec.ingressClassName: traefik`
  - `spec.rules[].host: dtrack.logiki.co.uk`
  - `spec.tls[].secretName: <INGRESS_TLS_SECRET_NAME>`
- Confirm DNS points `dtrack.logiki.co.uk` to the Traefik load balancer.
- Browse to `https://dtrack.logiki.co.uk` and confirm the UI loads.
