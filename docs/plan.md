# Plan – dependency-track-deploy

## 1) Contract with the Traefik ingress repository

This repository assumes:

- Traefik is already installed and functioning in the cluster.
- Traefik has an ingress class name (default assumed here: `traefik`).
- The cluster has a working external access path to the Traefik entrypoint.

This repository only creates the Dependency-Track `Ingress` resources via the official chart.

## 2) Deployment flow

1. Resolve configuration values (prefer Environment Variables over Secrets, same key name).
2. Azure login (Service Principal client secret).
3. Fetch AKS credentials and convert kubeconfig using `kubelogin`.
4. Ensure namespace `dependency-track` exists.
5. Create/update:
   - Image pull secret in `dependency-track`.
   - TLS secret in `dependency-track` from `WILDCARD_CRT`/`WILDCARD_KEY`.
   - Optional: app config secret (if any of the supported keys are set).
6. Render `helm/dependency-track/values.generated.yaml` from `values.template.yaml`.
7. `helm upgrade --install` the `dependencytrack/dependency-track` chart with `--wait --atomic`.
8. Post checks:
   - pods ready
   - ingress created

## 3) Required secrets/variables summary

### Minimum to deploy

- Azure: `DEPLOY_CLIENT_ID`, `DEPLOY_SECRET`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`
- AKS: `AKS_RESOURCE_GROUP`, `AKS_CLUSTER_NAME`
- Ingress: `DTRACK_INGRESS_HOST`, `DTRACK_INGRESS_CLASS_NAME`, `INGRESS_TLS_SECRET_NAME`, `WILDCARD_CRT`, `WILDCARD_KEY`
- Nexus pull: `NEXUS_DOCKER_SERVER`, `NEXUS_DOCKER_USERNAME`, `NEXUS_DOCKER_PASSWORD`, `IMAGE_PULL_SECRET_NAME`
- Images: `DTRACK_IMAGE_REGISTRY` (+ optional repositories/tags)

### Optional

- API server config env (external DB, etc.) via `DTRACK_APP_CONFIG_SECRET_NAME` + relevant env vars.
