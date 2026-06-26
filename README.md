# Vault Pull Secrets

GitHub Action for exporting Gaucho Racing Vault app secrets into a workflow job environment.

The action requests a GitHub Actions OIDC token, sends it to Vault, and appends the authorized secrets returned by Vault to `GITHUB_ENV`. Vault decides access using its GitHub Actions rules, which match the workflow repository, Git ref, and requested app-secret selectors.

## Usage

```yaml
permissions:
  id-token: write
  contents: read

jobs:
  publish:
    runs-on: ubuntu-latest
    steps:
      - uses: Gaucho-Racing/vault-pull-secrets@main
        with:
          secrets: |
            pypi.publish_token
            mapache-prod.sentinel_client_id

      - run: ./scripts/publish.sh
        env:
          PYPI_PUBLISH_TOKEN: ${{ env.PUBLISH_TOKEN }}
          SENTINEL_CLIENT_ID: ${{ env.SENTINEL_CLIENT_ID }}
```

## Inputs

| Input | Required | Default | Description |
| --- | --- | --- | --- |
| `secrets` | Yes | | Newline or comma separated Vault app-secret selectors to export. |
| `vault_url` | No | `https://vault.gauchoracing.com` | Base URL for the Vault API. |
| `audience` | No | `gaucho-racing-vault` | OIDC audience Vault expects when validating the GitHub token. |

Secret selectors use `application.secret`, for example `pypi.publish_token`.

Vault exports each selected secret using the secret key converted to an environment variable name:

| Selector | Environment Variable |
| --- | --- |
| `pypi.publish_token` | `PUBLISH_TOKEN` |
| `mapache-prod.sentinel_client_id` | `SENTINEL_CLIENT_ID` |

## Vault Setup

Create a GitHub Actions rule in Vault settings that allows the calling repository and ref to access the requested selectors.

Example rule:

| Field | Value |
| --- | --- |
| Repository patterns | `gaucho-racing/mapache` |
| Ref patterns | `refs/heads/main` |
| Secret selectors | `pypi.publish_token` |

Patterns can include `*`, such as `gaucho-racing/*`, `refs/tags/v*`, or `pypi.*`.

## Audience

The `audience` input is sent to GitHub when requesting the OIDC token. GitHub places it in the token's `aud` claim, and Vault rejects the token unless that audience matches Vault's configured `GITHUB_ACTIONS_OIDC_AUDIENCE`.

The default action audience is `gaucho-racing-vault`, matching Vault's default.

Most workflows should not override `audience`. Only set it when calling a Vault deployment configured with a different expected audience.

## Sanity Test

The quickest end-to-end test is to create a temporary GitHub Actions rule in Vault for a low-risk test secret and run a manual workflow from the allowed repo/ref.

```yaml
name: Vault secret smoke test

on:
  workflow_dispatch:

permissions:
  id-token: write
  contents: read

jobs:
  smoke:
    runs-on: ubuntu-latest
    steps:
      - uses: Gaucho-Racing/vault-pull-secrets@main
        with:
          secrets: pypi.publish_token

      - name: Verify secret was exported
        run: |
          test -n "${PUBLISH_TOKEN:-}"
          echo "PUBLISH_TOKEN is available"
```

This verifies the full path: GitHub OIDC issuance, Vault token validation, rule matching, secret resolution, and `GITHUB_ENV` export.

Do not print secret values. Check only that the expected environment variable is present.
