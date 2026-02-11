# Dependency-Track Deploy (AKS)

This repository deploys OWASP Dependency-Track to an AKS cluster using the official Helm chart (mirrored in an internal Helm repository) and exposes it via Traefik Ingress.

## What this does

- Deploys **Dependency-Track** via Helm (`upgrade --install`) into a target namespace.
- Pulls images from an **internal registry** using a generated `kubernetes.io/dockerconfigjson` image pull secret.
- Creates/updates:
  - Namespace
  - Image pull secret
  - TLS secret (from `WILDCARD_CRT`/`WILDCARD_KEY`)
  - App config secret containing Postgres connection parameters
  - Secret-key secret (`secret.key`) used by Dependency-Track for encryption
- Enforces **secret-key immutability**: the workflow verifies the in-cluster key matches the **mastered** value you provide; it fails fast on drift.

## Workflow

`.github/workflows/deploy-dependency-track.yaml`

Jobs:

1. **render-values-artifact** (only when `dtrack_debug=true`)
   - Renders `helm/dependency-track/values.template.yaml` into a concrete `values.generated.yaml`.
   - Uploads it as an artifact.

2. **deploy**
   - Logs into Azure with service principal credentials.
   - Obtains AKS kubeconfig and converts it for `azurecli` auth via `kubelogin`.
   - Creates/updates the required Kubernetes secrets.
   - Deploys Dependency-Track via Helm.

3. **cluster-debug-bundle** (only when `dtrack_debug=true`, runs even if `deploy` fails)
   - Collects namespace state (`kubectl get`, events, describe, logs) and helm status/history/values.
   - Uploads a debug bundle artifact.

### Important: debug mode changes Helm behavior

When `dtrack_debug=true` the workflow **does not use `--atomic`** on the Helm install/upgrade. This is deliberate so that if the deployment fails, resources remain available for inspection and the debug bundle can capture them.

- Normal runs (`dtrack_debug=false`) use `--wait --timeout ... --atomic`.
- Debug runs (`dtrack_debug=true`) use `--wait --timeout ...` and add `--debug`.

If you run with debug enabled and the release fails, you may need to clean up manually:

```bash
helm -n dependency-track uninstall dependency-track
```

## Required GitHub Environment configuration

Define these as **GitHub Environment variables/secrets** (the workflow resolves **vars first**, then **secrets**).

### Azure / AKS

| Name | Type | Notes |
|---|---|---|
| `DEPLOY_CLIENT_ID` | var/secret | App (client) ID for the deployment service principal |
| `DEPLOY_SECRET` | secret | Client secret for the service principal |
| `AZURE_TENANT_ID` | var/secret | Tenant ID |
| `AZURE_SUBSCRIPTION_ID` | var/secret | Subscription containing the AKS cluster |
| `AKS_RESOURCE_GROUP` | var/secret | Resource group containing the AKS cluster |
| `AKS_CLUSTER_NAME` | var/secret | AKS cluster name |

### Internal registry (image pull)

| Name | Type | Notes |
|---|---|---|
| `REGISTRY_SERVER` | var/secret | e.g. `docker-hosted-nexus.example.com` |
| `REGISTRY_USERNAME` | var/secret | Registry username |
| `REGISTRY_PASSWORD` | secret | Registry password |

### TLS (Ingress)

| Name | Type | Notes |
|---|---|---|
| `WILDCARD_CRT` | secret | Raw PEM (must include `-----BEGIN CERTIFICATE-----`) |
| `WILDCARD_KEY` | secret | Raw PEM private key |

### Postgres (Dependency-Track)

| Name | Type | Notes |
|---|---|---|
| `ALPINE_DATABASE_URL` | var/secret | JDBC URL preferred (example below). **Must not embed username/password.** |
| `ALPINE_DATABASE_USERNAME` | var/secret | Postgres username |
| `ALPINE_DATABASE_PASSWORD` | secret | Postgres password |
| `ALPINE_DATABASE_DRIVER` | var/secret | Optional. Defaults to `org.postgresql.Driver`. **Required for Azure Postgres Flexible Server**. Legacy alias: `DTRACK_ALPINE_DATABASE_DRIVER`. |

Example `ALPINE_DATABASE_URL`:

- `jdbc:postgresql://db.example.internal:5432/dependencytrack?sslmode=require`

### Secret key (encryption)

| Name | Type | Notes |
|---|---|---|
| `DTRACK_SECRET_KEY` | secret | **Base64** content for `secret.key` (the workflow verifies drift) |

## Common optional variables

| Name | Default | Notes |
|---|---:|---|
| `DTRACK_NAMESPACE` | `dependency-track` | Target namespace |
| `DTRACK_RELEASE_NAME` | `dependency-track` | Helm release name |
| `DTRACK_HELM_REPO_URL` | `https://nexus.example/repository/helm-hosted` | Internal Helm repo URL |
| `DTRACK_CHART_VERSION` | `1.0.0` | Chart version in internal repo |
| `DTRACK_INGRESS_HOST` | *(required)* | Hostname for the UI ingress |
| `INGRESS_TLS_SECRET_NAME` | `wildcard-tls` | TLS secret name |
| `IMAGE_PULL_SECRET_NAME` | `nexus-docker-creds` | Image pull secret name |
| `DTRACK_APP_CONFIG_SECRET_NAME` | `dependency-track-app-config` | Secret holding DB config |
| `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME` | `dtrack-secret-key` | Secret name storing `secret.key` |
| `DTRACK_SECRET_KEY_CREATE` | `false` | Rendered into Helm values (`common.secretKey.createSecret`). When `DTRACK_SECRET_KEY` is supplied, the workflow forces this to `false` to prevent chart-generated key drift. |
| `HELM_TIMEOUT` | `15m` | Helm wait timeout |

## Optional: Dependency-Track OIDC connector (application authentication)

If you want Dependency-Track to authenticate users via Entra ID (OIDC), set `DTRACK_OIDC_ENABLED=true` and provide the remaining variables.

**Behaviour:** when `DTRACK_OIDC_ENABLED` evaluates to `true` (case-insensitive), the workflow writes `ALPINE_OIDC_*` entries into the app-config env file (`${RUNNER_TEMP}/dtrack.env`) and recreates the Kubernetes secret `${DTRACK_APP_CONFIG_SECRET_NAME}`. When disabled, no `ALPINE_OIDC_*` entries are written (no drift).

| Name | Default | Notes |
|---|---:|---|
| `DTRACK_OIDC_ENABLED` | `false` | Gate. Must be the string `true` to enable rendering. |
| `DTRACK_OIDC_ISSUER` | *(empty)* | Typically `https://login.microsoftonline.com/<tenantId>/v2.0` |
| `DTRACK_OIDC_CLIENT_ID` | *(empty)* | Entra application (client) ID for the Dependency-Track OIDC connector |
| `DTRACK_OIDC_USER_CLAIM` | `preferred_username` | Username claim to map to D-Track principal |
| `DTRACK_OIDC_USER_PROVISIONING` | `true` | Must be `true`/`false` (written into the app-config secret) |
| `DTRACK_OIDC_TEAM_SYNCHRONIZATION` | `true` | Must be `true`/`false` (written into the app-config secret) |
| `DTRACK_OIDC_TEAMS_CLAIM` | `groups` | Group/team claim |

## GHES compatibility note

This repository targets **GitHub Enterprise Server**. Artifact actions must remain on **v3**:

- ✅ `actions/upload-artifact@v3`
- ✅ `actions/download-artifact@v3`
- ❌ `@actions/artifact v2.0.0+`, `upload-artifact@v4+`, `download-artifact@v4+` (not supported on GHES)

## See also

- `docs/plan.md` – design/requirements notes
- `docs/Dependency-Track Deploy - Authoritative Design & Compliance.md` – authoritative compliance reference
