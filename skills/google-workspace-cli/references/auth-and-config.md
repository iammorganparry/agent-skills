# `gws` Authentication, Config & Errors

Table of contents:
- [Checking auth state](#checking-auth-state)
- [Auth methods](#auth-methods)
- [Auth precedence](#auth-precedence)
- [Environment variables](#environment-variables)
- [Config file locations](#config-file-locations)
- [Exit codes](#exit-codes)
- [Model Armor sanitization](#model-armor-sanitization)

## Checking auth state

```bash
gws auth status          # JSON: auth_method, credential_source, storage, ...
```

`"auth_method": "none"` → not configured; pick a method below.
Subcommands: `gws auth {login|setup|status|export|logout}`.

## Auth methods

**1. Interactive OAuth (default for a workstation)**

```bash
gws auth login           # opens a browser, prompts for scopes, stores encrypted creds
```

Requires an OAuth *client* to exist. If none is configured, either run
`gws auth setup` (needs `gcloud`, auto-creates a GCP project + OAuth client and
enables APIs), or supply your own client via manual OAuth (below).

**2. Manual OAuth (no `gcloud`)**

1. In Google Cloud Console, configure the OAuth consent screen (User type
   **External**; add yourself under **Test users**).
2. Create a **Desktop** OAuth client, download the JSON, and save it to:
   `~/.config/gws/client_secret.json`
   (or export `GOOGLE_WORKSPACE_CLI_CLIENT_ID` + `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET`).
3. `gws auth login`

**3. Service account (server-to-server)**

```bash
export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/path/to/service-account.json
gws drive files list
```

**4. Headless / CI**

On an already-authenticated machine, export creds; move them to the target:

```bash
gws auth export --unmasked > credentials.json         # or: gws auth export
export GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE=/path/to/credentials.json
```

**5. Pre-obtained access token (highest priority, short-lived)**

```bash
export GOOGLE_WORKSPACE_CLI_TOKEN=$(gcloud auth print-access-token)
```

## Auth precedence (highest → lowest)

1. `GOOGLE_WORKSPACE_CLI_TOKEN`
2. `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE`
3. Encrypted local credentials (from `gws auth login`)
4. Plaintext `~/.config/gws/credentials.json`

## Environment variables

| Variable | Purpose |
|---|---|
| `GOOGLE_WORKSPACE_CLI_TOKEN` | Pre-obtained OAuth2 access token (wins over everything) |
| `GOOGLE_WORKSPACE_CLI_CREDENTIALS_FILE` | Path to credentials / service-account JSON |
| `GOOGLE_WORKSPACE_CLI_CLIENT_ID` | OAuth client ID (for `gws auth login`) |
| `GOOGLE_WORKSPACE_CLI_CLIENT_SECRET` | OAuth client secret (paired with client ID) |
| `GOOGLE_WORKSPACE_CLI_CONFIG_DIR` | Override config dir (default `~/.config/gws`) |
| `GOOGLE_WORKSPACE_CLI_KEYRING_BACKEND` | `keyring` (default) or `file` to store creds on disk |
| `GOOGLE_WORKSPACE_PROJECT_ID` | Override GCP project for quota/billing |
| `GOOGLE_WORKSPACE_CLI_SANITIZE_TEMPLATE` | Default Model Armor template |
| `GOOGLE_WORKSPACE_CLI_SANITIZE_MODE` | `warn` (default) or `block` |
| `GOOGLE_WORKSPACE_CLI_LOG` | Stderr log level, e.g. `gws=debug` |
| `GOOGLE_WORKSPACE_CLI_LOG_FILE` | Directory for JSON logs (daily rotation) |

A `.env` file in the working directory is loaded automatically (dotenvy).

## Config file locations

```
~/.config/gws/                     # config root (override: GOOGLE_WORKSPACE_CLI_CONFIG_DIR)
~/.config/gws/client_secret.json   # OAuth client credentials
~/.config/gws/credentials.enc      # encrypted user credentials (keyring backend)
~/.config/gws/credentials.json     # plaintext user credentials (file backend / fallback)
```

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | API error (Google returned 4xx/5xx) |
| 2 | Auth error (invalid/expired credentials) — run `gws auth login` |
| 3 | Validation error (unknown service or bad flags) — re-check with `--help`/`schema` |
| 4 | Discovery error (failed to fetch schema) |
| 5 | Internal error |

## Model Armor sanitization

`--sanitize <projects/P/locations/L/templates/T>` filters API *responses*
through a Model Armor template (requires the `cloud-platform` scope). Mode is
`warn` by default or `block` via `GOOGLE_WORKSPACE_CLI_SANITIZE_MODE`. Only
needed when handling untrusted user-generated content; omit otherwise.
