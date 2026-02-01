# Changelog

## v0.1.1
- Reused the tested **Azure login / AKS credentials / Helm install** step patterns from `deploy-traefik.yaml` (az cli login + kubelogin spn conversion).
- Added pre-run resolver (`vars` preferred over `secrets`) and logs source selection without leaking secret values.
- Helm timeout parsing aligned with Traefik workflow (`10` -> `10m`).

## v0.1.0
- Initial repository skeleton for deploying Dependency-Track behind an existing Traefik ingress.
