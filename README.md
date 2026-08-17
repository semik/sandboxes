# Sandboxes

## terraform-az container

Is designed for Terraform development with Azure. It includes the Azure CLI (`az`), Terraform, Kubernetes tools (`kubectl`, `helm`, `kubelogin`), k9s for Kubernetes cluster management, and Claude Code (`claude`).

Build:

```bash
podman build -f Dockerfile-terraform-az -t terraform-az:latest .
```

Run the container, mounting your current directory to `/work`:

```bash
./run-terraform-az.sh
```

Run a one-off command (example):

```bash
./run-terraform-az.sh terraform version
```

Equivalent `podman run` without the script:

```bash
podman run --hostname azure-env --name azure-env -it --rm --userns=keep-id \
	-e "HOME=/home/ubuntu" \
	-e "CLAUDE_CONFIG_DIR=/home/ubuntu/.claude" \
	-v "$HOME/Sync/3K/azure-env:/home/ubuntu:Z" \
	-v "$HOME/.azure:/home/ubuntu/.azure:Z" \
	-v "$HOME/.local/share/azure-env-claude:/home/ubuntu/.claude:Z" \
	-v "$PWD:/work:Z" \
	terraform-az:latest
```

Notes:

- The image default command is `bash -l` so bash-completion loads.
- The working directory is `/work`, set by `WORKDIR` in the image.
- If you run the script from `$HOME` it skips the `/work` mount rather than
  exposing your entire home directory to the container.

## Included tools

- Azure CLI (`az`)
- Terraform / OpenTofu (via `tenv`)
- Kubernetes CLI (`kubectl`)
- Helm
- kubelogin
- k9s (Kubernetes cluster management)
- Claude Code (`claude`)

## Mounts and overrides

Every path is overridable with an environment variable:

| Variable | Default | Mounted at |
| --- | --- | --- |
| `HOME_DIR_HOST` | `~/Sync/3K/azure-env` | `/home/ubuntu` — persistent sandbox home |
| `AZURE_DIR_HOST` | `~/.azure` | `/home/ubuntu/.azure` — your real host Azure auth |
| `CLAUDE_DIR_HOST` | `~/.local/share/azure-env-claude` | `/home/ubuntu/.claude` — Claude Code config |
| `WORK_DIR_HOST` | `$PWD` | `/work` |

Also: `IMAGE`, `NAME`, `HOSTNAME_VALUE`, `CONTAINER_HOME`.

`CLAUDE_DIR_HOST` deliberately points **outside `~/Sync`**. The sandbox home is a
Syncthing folder, and `~/.claude/.credentials.json` holds a long-lived OAuth
token that should not be replicated to other machines. The script also sets
`CLAUDE_CONFIG_DIR` so that `~/.claude.json` — a separate file holding the OAuth
account, onboarding state and per-project trust — lands in the same directory
instead of in the synced home.

An empty `.claude/` placeholder does appear in the sandbox home, because a
nested bind mount needs a mountpoint there. It stays empty (the same is true of
`.azure/`); the script pre-creates both so they are owned by you rather than by
a user-namespace-mapped uid.

## Using k9s

To launch k9s in the container:

```bash
./run-terraform-az.sh k9s
```

## Using Claude Code

```bash
./run-terraform-az.sh claude
```

First run triggers an OAuth login. The container prints a URL — open it on the
host. The localhost callback usually cannot reach the container, so the browser
falls back to showing a code; paste it at the `Paste code here if prompted`
prompt. This happens **once**: `CLAUDE_DIR_HOST` persists across containers even
though the container itself is `--rm`.

Do **not** set `ANTHROPIC_API_KEY` in the environment. It takes precedence over
your subscription login, so you would silently get billed per token. The wrapper
passes no environment through today — keep it that way.

The version is pinned by apt via the `CLAUDE_CODE_VERSION` build arg, and
`DISABLE_AUTOUPDATER=1` is set so it does not update itself out from under the
image. To bump:

```bash
podman build -f Dockerfile-terraform-az --build-arg CLAUDE_CODE_VERSION=2.1.130-1 -t terraform-az:latest .
```

Build with `--build-arg CLAUDE_CODE_VERSION=` (empty) to take whatever is newest
in the repo's stable channel.

### What this sandbox does and does not protect

It is a **reproducibility boundary, not a security boundary.** The container has
your live host `~/.azure` — real Azure refresh tokens — bind-mounted
read-write, and unrestricted outbound network. Anything running inside, Claude
included, can reach both. Prefer `/permissions` auto mode over
`--dangerously-skip-permissions`.

No egress filtering is configured. If you add an allowlist later, it needs at
minimum `api.anthropic.com`, `claude.ai`, `claude.com`, `platform.claude.com`,
`downloads.claude.ai`, `code.claude.com`, `statsig.com`, `sentry.io`, plus the
Azure, Kubernetes, apt and GitHub endpoints the other tools use. Note that
Anthropic's own reference `init-firewall.sh` predates several of those. Doing
this under rootless podman also means `--cap-add=NET_ADMIN --cap-add=NET_RAW`,
which is the genuinely awkward part.

### Customizing containers $HOME

#### Install tofu:
```
export TOFU_VERSION="1.10.6"
tenv tofu install "${TOFU_VERSION}"
tenv tofu use "${TOFU_VERSION}"
# this is quite suprising as `tenv tofu use doesn't activate this
ln -sf "${HOME}/.tenv/OpenTofu/${TOFU_VERSION}/tofu" "${HOME}/bin/tofu"
```

#### Get Kubernets login credentials
```
az aks get-credentials --resource-group <RG> --name <AKS_CLUSTER_NAME>
kubelogin convert-kubeconfig -l azurecli
```
