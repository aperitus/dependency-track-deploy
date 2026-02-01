# Dependency-Track (AKS) — Requirements BOM (GitHub Actions)

**Scope**: Dedicated application repository deploys **Dependency-Track** to AKS via **GitHub Actions (GHES)** on a **self-hosted runner**. This repo assumes the **ingress-nginx baseline** is managed by a separate repository. Container images are pulled from **Nexus**. Azure authentication uses **Service Principal + client secret**.

---

## 1) Decisions and fixed parameters
- Application: Dependency-Track (official chart)
- Namespace: `dependency-track`
- Release name: `dependency-track`
- Ingress host: `dtrack.logiki.co.uk`
- Ingress controller: ingress-nginx (pre-installed)
- TLS secret: `INGRESS_TLS_SECRET_NAME` created in `dependency-track` from wildcard PEM material
- Images: overridden to Nexus for Dependency-Track components
- Sensitive app configuration: stored in Kubernetes Secret `dependency-track-app-config` to avoid Helm release history leakage

---

## 2) Runner prerequisites
- Self-hosted runner (Linux recommended) with:
  - `az` (Azure CLI)
  - `kubectl`
  - `helm`
  - `python3`
- Network egress from runner to:
  - Azure ARM / Entra endpoints
  - AKS API server endpoint

---

## 3) Workflow inputs (non-secret)
| Input | Required | Description |
|---|---:|---|
| `environment` | Yes | GitHub Environment name (e.g., `dev`) |
| `aks_resource_group` | Yes | AKS resource group name |
| `aks_cluster_name` | Yes | AKS cluster name |
| `use_admin_credentials` | No | Uses `az aks get-credentials --admin` |
| `dtrack_chart_version` | Yes | Pinned chart version |
| `helm_timeout` | Yes | Helm timeout (e.g., `10m`) |

---

## 4) GitHub Environment secrets

### Azure (Service Principal + secret)
| Secret | Required | Description |
|---|---:|---|
| `AZURE_TENANT_ID` | Yes | Entra tenant ID |
| `AZURE_SUBSCRIPTION_ID` | Yes | Subscription to target |
| `DEPLOY_CLIENT_ID` | Yes | Service Principal appId |
| `DEPLOY_SECRET` | Yes | Service Principal client secret |

### Nexus registry (Docker)
| Secret | Required | Description |
|---|---:|---|
| `REGISTRY_SERVER` | Yes | Registry host[:port], no scheme |
| `REGISTRY_USERNAME` | Yes | Username / token |
| `REGISTRY_PASSWORD` | Yes | Password / token |
| `IMAGE_PULL_SECRET_NAME` | Yes | Secret name created in `dependency-track` |

### TLS (wildcard)
| Secret | Required | Description |
|---|---:|---|
| `WILDCARD_CRT` | Yes | PEM certificate for `dtrack.logiki.co.uk` (wildcard ok) |
| `WILDCARD_KEY` | Yes | PEM private key matching `WILDCARD_CRT` |
| `INGRESS_TLS_SECRET_NAME` | Yes | Secret name created in `dependency-track` |

### Dependency-Track (required)
| Secret | Required | Description |
|---|---:|---|
| `DTRACK_DB_URL` | Yes | JDBC URL to external DB (chart-dependent) |

### Dependency-Track (optional)
| Secret | Required | Description |
|---|---:|---|
| `DTRACK_ADMIN_PASSWORD` | No | Initial admin password override |
| `DTRACK_BASE_URL` | No | Base/internal URL (if needed) |
| `DTRACK_PUBLIC_URL` | No | External URL used for redirects/links |
| `DTRACK_OIDC_ISSUER` | No | OIDC issuer URL |
| `DTRACK_OIDC_CONNECTOR_CLIENT_ID` | No | OIDC connector client ID |
| `DTRACK_OIDC_CONNECTOR_SECRET` | No | OIDC connector client secret |

### Optional overrides (environment variables)
- `DTRACK_APISERVER_IMAGE_REPOSITORY`
- `DTRACK_FRONTEND_IMAGE_REPOSITORY`
- `DTRACK_IMAGE_TAG`
- `DTRACK_HELM_REPO_URL` (if you proxy charts through Nexus)

---

## 5) Required cluster actions
- Create namespace `dependency-track` if missing.
- Create/update docker-registry Secret `IMAGE_PULL_SECRET_NAME` in `dependency-track`.
- Create/update TLS Secret `INGRESS_TLS_SECRET_NAME` in `dependency-track` from wildcard PEM.
- Create/update Secret `dependency-track-app-config` from environment values.
- `helm upgrade --install` Dependency-Track with:
  - images overridden to Nexus
  - `imagePullSecrets` set
  - ingress enabled and configured
  - `--wait --atomic --timeout`

---

## 6) Deliverables
### Deliverable A — Workflow YAML
A workflow that:
- logs into Azure using `DEPLOY_CLIENT_ID` / `DEPLOY_SECRET`
- fetches kubeconfig via `az aks get-credentials`
- creates/updates `IMAGE_PULL_SECRET_NAME` in `dependency-track`
- creates/updates `INGRESS_TLS_SECRET_NAME` from `WILDCARD_CRT/WILDCARD_KEY`
- creates `dependency-track-app-config` Secret (to keep secrets out of Helm values history)
- generates `/tmp/values.dependency-track.generated.yaml` without leaking secrets to logs
- installs/upgrades Dependency-Track with pinned chart version and atomic waits

### Deliverable B — Minimal values template
A minimal values template for the official Dependency-Track chart, structured to accept:
- Nexus repository overrides for images
- ingress host and TLS secret name
- imagePullSecrets
