# Publier CLI Releases

Binary releases for the [publier CLI](https://publier.net/docs/cli).

## Install

```sh
curl -fsSL https://github.com/publier/releases/raw/main/install.sh | sh
```

## CI action removed

The `publier-ci-claim` GitHub Action was removed on 2026-10-12. GitHub Actions
builds no longer claim a credential: the Publier CLI requests the job's OIDC
token itself, so the build job only needs `permissions: id-token: write`. See
the [deployment guide](https://publier.net/docs/deploy/deployment).
