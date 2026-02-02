# Plan – dependency-track-deploy

## 1) Contract with the Traefik ingress repository

This repository assumes:

- Traefik is already installed and functioning in the cluster.
- Traefik has an ingress class name (default assumed here: `traefik`).
- The cluster has a working external access path to the Traefik entrypoint.

This repository only creates the Dependency-Track `Ingress` resources via the official chart.

## 2) Deployment flow

The workflow is manually triggered via `workflow_dispatch` and requires selecting a GitHub Environment: `dev`, `preprod`, or `prod`.

1. Resolve configuration values (prefer GitHub **Environment variables** over **Environment secrets** for the same key name).
   - Implemented via inline workflow expressions (vars-first fallback to secrets), not a resolver script.
2. Azure login (Service Principal client secret).
3. Fetch AKS credentials and convert kubeconfig using `kubelogin`.
4. Ensure namespace `dependency-track` exists.
5. Create/update:
   - Image pull secret in `dependency-track`.
   - TLS secret in `dependency-track` from `WILDCARD_CRT`/`WILDCARD_KEY`.
   - App config secret (always created/updated) containing database configuration.
     - `DTRACK_DB_URL` is required and is mapped to `ALPINE_DATABASE_URL` for the API server.
     - If `ALPINE_DATABASE_*` keys are also provided, they override the defaults.
6. Render `helm/dependency-track/values.generated.yaml` from `values.template.yaml`.
7. `helm upgrade --install` the `dependencytrack/dependency-track` chart with `--wait --atomic`.
8. Post checks:
   - pods ready
   - ingress created

## 3) Required secrets/variables summary

This repo supports configuring each key as either a GitHub Environment **variable** or **secret**.
The workflow uses vars-first fallback to secrets inline (example: `vars.KEY != '' && vars.KEY || secrets.KEY`).
It echoes the resolved values early in the job; if a value was sourced from secrets, it should appear masked in logs.

### Minimum to deploy

- Azure: `DEPLOY_CLIENT_ID`, `DEPLOY_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- AKS: `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`
- Ingress: `DTRACK_INGRESS_HOST`, `DTRACK_INGRESS_CLASS_NAME`, `INGRESS_TLS_SECRET_NAME`, `WILDCARD_CRT`, `WILDCARD_KEY`
- Nexus pull: `NEXUS_DOCKER_SERVER`, `NEXUS_DOCKER_USERNAME`, `NEXUS_DOCKER_PASSWORD`, `IMAGE_PULL_SECRET_NAME`
- Database: `DTRACK_DB_URL` (JDBC URL; mapped to `ALPINE_DATABASE_URL` for the API server)
- Images: `DTRACK_IMAGE_REGISTRY` (+ optional repositories/tags)

### Optional

- Advanced DB env overrides (if you do not want to rely on `DTRACK_DB_URL`):
  - `ALPINE_DATABASE_MODE`, `ALPINE_DATABASE_URL`, `ALPINE_DATABASE_USERNAME`, `ALPINE_DATABASE_PASSWORD`
