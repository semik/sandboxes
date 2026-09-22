# Sandboxes

Podman sandboxes for working on multiple customers/environments from one
machine, with **per-environment isolation of login sessions and keys**: each
environment gets its own Azure login, its own Claude Code login, and its own
SSH keypair. Nothing is shared between environments, and the host's own
credentials are never mounted by default.

## The per-environment model

An environment named `<env>` consists of two directories under one base:

```
~/.sandboxes/<env>/            container home (/home/u)
  .azure/                        per-env Azure CLI login (az login inside)
  .claude/                       per-env Claude Code config + OAuth credentials
  .ssh/                          per-env SSH keypair + known_hosts
  .kube/  .config/  bin/  ...    everything else the tools write
~/.sandboxes/<env>.conf        the environment's definition (plain bash)
```

The conf sits **next to** the env home, never inside it: the home is
bind-mounted read-write into the container, and the conf is executed as bash
on the host, so nothing running in the sandbox may ever be able to rewrite
how it gets launched.

Only two things are mounted into the container: the environment home at
`/home/u` and your current directory at `/work`. There are no nested
credential mounts — `.azure`, `.claude` and `.ssh` are just subdirectories of
the home, so they are isolated per environment simply because each environment
has its own home.

The base directory defaults to `~/.sandboxes`. Override it with the
`SANDBOXES_BASE` environment variable, or persistently in
`~/.config/sandboxes.conf` (sourced by the script if present; it is executed
bash, so keep the `${VAR:-...}` form to let one-off overrides win):

```bash
# ~/.config/sandboxes.conf
SANDBOXES_BASE="${SANDBOXES_BASE:-$HOME/my/synced/folder}"
```

Point the base at a folder synchronized between your machines (Syncthing,
etc.) and environments — **credentials included** — follow you everywhere.
That is a real trade-off; see
[If the base is a synced folder](#if-the-base-is-a-synced-folder).

## Usage

```bash
./sandbox.sh init <env>        # create a new environment (home dir, conf, ssh key)
./sandbox.sh <env>             # shell in the environment, $PWD mounted at /work
./sandbox.sh <env> <cmd...>    # one-off command, e.g. ./sandbox.sh acme terraform plan
./sandbox.sh list              # list environments
```

There is no default environment — you always name one. That is the point:
running "whatever env was last used" against the wrong customer is the
accident this layout prevents.

First-time setup inside a fresh environment:

```bash
./sandbox.sh <env>
az login                       # per-environment Azure session
claude                         # per-environment Claude login (see below)
```

## The conf file

`init` writes `$SANDBOXES_BASE/<env>.conf` with every setting commented
out — a fresh environment is pure convention. The conf is sourced by
`sandbox.sh` (it is executed bash: don't source confs you didn't write) and
may reference `$ENV_NAME` and `$SANDBOXES_BASE`, which are set by then.
Available variables and their derived defaults:

| Variable | Default | Meaning |
| --- | --- | --- |
| `HOME_DIR_HOST` | `$SANDBOXES_BASE/<env>` | mounted at `/home/u` |
| `WORK_DIR_HOST` | `$PWD` | mounted at `/work`; pin a project dir here |
| `IMAGE` | `sandbox:latest` | container image |
| `HOSTNAME_VALUE` | `<env>` | container hostname |
| `NAME` | `<env>` | container name prefix (timestamp appended) |
| `CONTAINER_HOME` | `/home/u` | home path inside the container |
| `AZURE_DIR_HOST` | *(empty)* | opt-out: set to `$HOME/.azure` to share the **host** Azure login with this env |
| `EXTRA_MOUNTS` | *(unset)* | bash array of extra bind mounts, `HOST:CONTAINER` (`:Z` appended) or `HOST:CONTAINER:opts` |
| `DEFAULT_CMD` | *(unset)* | bash array: command to start when none is given on the CLI, e.g. `DEFAULT_CMD=(zellij attach --create "$ENV_NAME")` for a zellij session named after the env; the image default is `bash -l`. An explicit command (`./sandbox.sh <env> bash -l`) always wins |

`EXTRA_MOUNTS` mounts specific host paths into the environment instead of
copying them, e.g. a customer's kubeconfig:

```bash
EXTRA_MOUNTS=("$HOME/proj/acme/kubeconfig:/home/u/.kube/config:ro,Z")
```

Mountpoints nested in the env home are pre-created host-side so they stay
owned by you. Caveat for single-**file** mounts: tools that rewrite a file
atomically (rename-and-replace — `kubectl config`, `kubelogin`, `az aks
get-credentials` all do) break the bind, leaving host and container looking
at different files. If anything inside will update the credential, mount its
containing directory (e.g. `...:/home/u/.kube`) instead of the file.

Precedence: command-line environment variables beat the conf, which beats the
derived defaults — as long as the conf keeps the generated `${VAR:-...}` form.
A plain `VAR=...` assignment in a conf is the escape hatch to hard-pin a value
against command-line overrides.

```bash
IMAGE=sandbox:test ./sandbox.sh acme terraform version   # one-off override
```

## If the base is a synced folder

With `SANDBOXES_BASE` in a folder replicated between machines (Syncthing or
similar), everything in an environment home replicates too: Azure MSAL token
caches, Claude's `.claude/.credentials.json` OAuth token, and SSH private
keys. That is the appeal — one login per environment, valid on all your
machines — but be aware what it means:

- Your synced device set **is** the trust boundary. Every synced device
  holds live credentials for every environment.
- Put a passphrase on the SSH keys (`init` reminds you:
  `ssh-keygen -p -f <env-home>/.ssh/id_ed25519`).
- Avoid running the same environment on two machines at the same time —
  concurrently rewritten token caches and `.bash_history` produce sync
  conflict files.
- The sync tool must preserve permissions (in Syncthing: don't enable
  "Ignore Permissions"), otherwise a private key can arrive as `0644` on
  another machine and ssh will refuse it; `chmod 600` fixes it.

## SSH

Each environment gets its own ed25519 keypair, generated by `init` into
`<env-home>/.ssh/id_ed25519` with the comment `<env>-sandbox`. Register the
printed public key with that customer's Git server (GitHub deploy key, Azure
DevOps, ...). A compromised environment leaks only that customer's key.
`known_hosts` lives in the same directory and is populated on first use.

## Azure

Each environment holds its own `az login` session in `<env-home>/.azure`. The
host's `~/.azure` is never mounted by default, so the host CLI and every
environment have fully independent Azure identities — switching customers no
longer means re-logging the host `az`.

For a personal/lab environment where sharing the host login is convenient,
uncomment `AZURE_DIR_HOST` in its conf; the wrapper then bind-mounts the host
`~/.azure` over the environment's. (The mountpoint is pre-created by the
script so it stays owned by you rather than by a user-namespace-mapped uid.)

Beware of files created *inside* a mountpoint while no container is running:
they get shadowed by the mount at runtime and linger, synced, on disk.

## Using Claude Code

```bash
./sandbox.sh <env> claude
```

First run per environment triggers an OAuth login. The container prints a
URL — open it on the host. The localhost callback usually cannot reach the
container, so the browser falls back to showing a code; paste it at the
`Paste code here if prompted` prompt. This happens once per environment: the
config persists in `<env-home>/.claude` even though the container itself is
`--rm`. The wrapper sets `CLAUDE_CONFIG_DIR` so that `~/.claude.json` — the
file holding the OAuth account, onboarding state and per-project trust —
lands inside `.claude/` too, keeping all Claude state in one directory.

Do **not** set `ANTHROPIC_API_KEY` in the environment. It takes precedence
over your subscription login, so you would silently get billed per token. The
wrapper passes no environment through today — keep it that way.

The version is pinned by apt via the `CLAUDE_CODE_VERSION` build arg, and
`DISABLE_AUTOUPDATER=1` is set so it does not update itself out from under the
image. To bump:

```bash
podman build --build-arg CLAUDE_CODE_VERSION=2.1.130-1 -t sandbox:latest .
```

Build with `--build-arg CLAUDE_CODE_VERSION=` (empty) to take whatever is
newest in the repo's stable channel.

## The sandbox image

Designed for Terraform development with Azure. Included tools:

- Azure CLI (`az`)
- Terraform / OpenTofu (via `tenv`)
- Kubernetes CLI (`kubectl`)
- Helm
- kubelogin
- k9s (Kubernetes cluster management)
- Claude Code (`claude`)
- OpenSSH client (`ssh`, `ssh-keygen`)
- Midnight Commander (`mc`)
- zellij and tmux (terminal multiplexers)

Build:

```bash
podman build -t sandbox:latest .
```

Equivalent `podman run` without the script:

```bash
podman run --hostname <env> --name <env>-$(date +%Y%m%d-%H%M%S) -it --rm --userns=keep-id \
	-e "HOME=/home/u" \
	-e "CLAUDE_CONFIG_DIR=/home/u/.claude" \
	-v "$HOME/.sandboxes/<env>:/home/u:Z" \
	-v "$PWD:/work:Z" \
	sandbox:latest
```

Notes:

- The image default command is `bash -l` so bash-completion loads.
- The working directory is `/work`, set by `WORKDIR` in the image.
- If you run the script from `$HOME`, or from a directory containing
  `$SANDBOXES_BASE` (which would hand the container every environment's
  credentials and the host-executed conf files), it skips the `/work` mount
  rather than exposing them to the container.
- `--userns=keep-id` maps your host uid onto the container's `u` user;
  the image bakes in uid/gid 1000, so a host uid other than 1000 won't line up.
- The `:Z` labels are no-ops without SELinux but kept for hosts that have it.

### What this sandbox does and does not protect

It is a **reproducibility and per-customer boundary, not a security
boundary.** The container no longer sees the host `~/.azure`, so the blast
radius of anything running inside — Claude included — is one environment's
credentials, not your host identity. But within the environment it has those
credentials read-write and unrestricted outbound network. Prefer
`/permissions` auto mode over `--dangerously-skip-permissions`.

No egress filtering is configured. If you add an allowlist later, it needs at
minimum `api.anthropic.com`, `claude.ai`, `claude.com`, `platform.claude.com`,
`downloads.claude.ai`, `code.claude.com`, `statsig.com`, `sentry.io`, plus the
Azure, Kubernetes, apt and GitHub endpoints the other tools use. Note that
Anthropic's own reference `init-firewall.sh` predates several of those. Doing
this under rootless podman also means `--cap-add=NET_ADMIN --cap-add=NET_RAW`,
which is the genuinely awkward part.

## Migrating a pre-existing sandbox home

The old single-environment layout kept Claude config in
`~/.local/share/azure-env-claude` and mounted the host `~/.azure`. To adopt
an existing home dir (example: `azure-env`, with `env_home` standing for
`$SANDBOXES_BASE/azure-env`):

```bash
./sandbox.sh init azure-env                # adopts the existing home, adds conf + .ssh + key

# Claude: merge the old external config into the env home (no re-login needed)
cp -a ~/.local/share/azure-env-claude/. <env_home>/.claude/
# ...after a verified run: rm -rf ~/.local/share/azure-env-claude

# Azure: clear stale pre-mount leftovers, then fresh login inside the container
rm -rf <env_home>/.azure/* <env_home>/.azure/.[!.]*
./sandbox.sh azure-env az login
# (alternative to a fresh login: cp -a ~/.azure/. <env_home>/.azure/)
```

If a leftover mountpoint ended up owned by a podman-mapped uid (e.g.
`100000`), plain `rm` fails; fix it from inside the user namespace:

```bash
podman unshare rm -rf <env_home>/.azure   # then re-run init / mkdir
```

## Using k9s

```bash
./sandbox.sh <env> k9s
```

## Customizing containers $HOME

### Install tofu:
```
export TOFU_VERSION="1.10.6"
tenv tofu install "${TOFU_VERSION}"
tenv tofu use "${TOFU_VERSION}"
# this is quite suprising as `tenv tofu use doesn't activate this
ln -sf "${HOME}/.tenv/OpenTofu/${TOFU_VERSION}/tofu" "${HOME}/bin/tofu"
```

### Get Kubernets login credentials
```
az aks get-credentials --resource-group <RG> --name <AKS_CLUSTER_NAME>
kubelogin convert-kubeconfig -l azurecli
```
