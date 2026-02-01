# Changelog

## v0.1.0

- Initial companion repository for deploying Dependency-Track to AKS.
- GHES GitHub Actions workflow using Azure Service Principal + client secret (no OIDC).
- Idempotent creation of:
  - namespace `dependency-track`
  - image pull secret `IMAGE_PULL_SECRET_NAME`
  - TLS secret `INGRESS_TLS_SECRET_NAME`
  - app config secret `dependency-track-app-config`
- Chart deployment using pinned `dependency-track/dependency-track` version, `--wait --atomic --timeout`.
- Pre-run input resolver that prefers Environment vars over secrets and logs selection (secrets redacted).
