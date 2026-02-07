# Plan – dependency-track-deploy

## 1) Contract with the Traefik ingress repository

This repository assumes:

- Traefik is already installed and functioning in the cluster.
- Traefik has an ingress class name (default assumed here: `traefik`).
- The cluster has a working external access path to the Traefik entrypoint.

This repository only deploys Dependency-Track and creates the necessary `Ingress` resources via the official chart.

## 2) Deployment flow

The workflow is manually triggered via `workflow_dispatch` and requires selecting a GitHub Environment: `dev`, `preprod`, or `prod`.

1. Resolve configuration values (prefer GitHub **Environment variables** over **Environment secrets** for the same key name).
   - Implemented via inline workflow expressions (vars-first fallback), not a resolver script.
2. Azure login (Service Principal client secret).
   - OIDC/Entra federation is documented as an *advanced* option but is not required for baseline operation.
3. Fetch AKS credentials and convert kubeconfig using `kubelogin`.
4. Ensure namespace `dependency-track` exists.
5. Create/update:
   - Image pull secret in `dependency-track`.
   - TLS secret in `dependency-track` from `WILDCARD_CRT`/`WILDCARD_KEY`.
   - **Secret key secret** (crypto key) in `dependency-track`.
     - The key is mastered externally in Key Vault and synced into GitHub as `DTRACK_SECRET_KEY`.
     - The workflow creates it if missing and **fails** if it detects drift (refuses rotation).
   - App config secret (always created/updated) containing database configuration.
     - External Postgres is configured via `ALPINE_DATABASE_URL` / `ALPINE_DATABASE_USERNAME` / `ALPINE_DATABASE_PASSWORD`.
     - `ALPINE_DATABASE_URL` must be JDBC and start with `jdbc:postgresql://`.
6. Render a temporary `values.generated.yaml` (non-sensitive) for Helm.
7. `helm upgrade --install` the `dependencytrack/dependency-track` chart with `--wait --atomic`.
8. Post checks:
   - pods listed
   - ingress listed

## 3) Debug mode

If the workflow input `debug=true`:

- The deploy job enables additional application logging (`LOGGING_LEVEL=DEBUG`).
- A separate job `debug-artifacts` runs with `if: always()` and uploads troubleshooting artefacts (safe to share), including:
  - `values.generated.yaml` used for Helm
  - `helm status` / `helm get values`
  - `kubectl get ...` outputs
  - pod describe and logs tail for api-server
  - events

## 4) Required secrets/variables summary

This repo supports configuring each key as either a GitHub Environment **variable** or **secret**.
The workflow uses vars-first fallback to secrets inline (example: `vars.KEY != '' && vars.KEY || secrets.KEY`).

### Minimum to deploy

- Azure: `DEPLOY_CLIENT_ID`, `DEPLOY_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- AKS: `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`
- Ingress TLS: `INGRESS_TLS_SECRET_NAME`, `WILDCARD_CRT`, `WILDCARD_KEY`
- Registry pull (Nexus): `REGISTRY_SERVER`, `REGISTRY_USERNAME`, `REGISTRY_PASSWORD`, `IMAGE_PULL_SECRET_NAME`
- Database (required): `ALPINE_DATABASE_URL` + `ALPINE_DATABASE_USERNAME` + `ALPINE_DATABASE_PASSWORD`
- Secret key mastery (required): `DTRACK_SECRET_KEY` + `DTRACK_SECRET_KEY_EXISTING_SECRET_NAME`

