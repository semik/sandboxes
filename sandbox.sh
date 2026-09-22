#!/usr/bin/env bash
set -euo pipefail

# Per-environment sandbox launcher. Each environment <env> is a self-contained
# container home at $SANDBOXES_BASE/<env> (its own .azure, .claude, .ssh, ...)
# plus a sibling conf file at $SANDBOXES_BASE/<env>.conf -- next to the home,
# never inside it, so the container cannot rewrite its own launch config.
# Point the base at a folder synchronized between your machines and
# environments -- credentials included -- follow you; see the README.
#
# Optional per-user config, sourced before defaults apply. Set your own base
# there, e.g.: SANDBOXES_BASE="${SANDBOXES_BASE:-$HOME/my/synced/folder}"
USER_CONF="${SANDBOX_USER_CONF:-$HOME/.config/sandboxes.conf}"
if [[ -f "$USER_CONF" ]]; then
  # shellcheck disable=SC1090
  source "$USER_CONF"
fi

SANDBOXES_BASE="${SANDBOXES_BASE:-$HOME/.sandboxes}"
CONF_DIR="${SANDBOX_CONF_DIR:-$SANDBOXES_BASE}"

SCRIPT_NAME="$(basename "$0")"

list_envs() {
  local confs=("$CONF_DIR"/*.conf) c
  if [[ -e "${confs[0]}" ]]; then
    echo "Available environments (${CONF_DIR}):"
    for c in "${confs[@]}"; do
      echo "  $(basename "$c" .conf)"
    done
  else
    echo "No environments defined yet (no *.conf in ${CONF_DIR})."
  fi
}

usage() {
  cat <<EOF
Usage: ${SCRIPT_NAME} <env> [cmd...]   run a container for environment <env>
       ${SCRIPT_NAME} init <env>       create a new environment (home dir, conf, ssh key)
       ${SCRIPT_NAME} list             list environments

EOF
  list_envs
}

validate_env_name() {
  local env="$1"
  # 'sandboxes' is the conf dir itself; 'init'/'list' are subcommands.
  case "$env" in
    init|list|sandboxes)
      echo "[ERROR] '$env' is a reserved name and cannot be used as an environment." >&2
      exit 1
      ;;
  esac
  if [[ ! "$env" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; then
    echo "[ERROR] Invalid environment name '$env' (allowed: letters, digits, '.', '_', '-')." >&2
    exit 1
  fi
}

cmd_init() {
  local env="$1"
  validate_env_name "$env"

  local conf="$CONF_DIR/$env.conf"
  if [[ -e "$conf" ]]; then
    echo "[ERROR] Environment '$env' already exists: $conf" >&2
    exit 1
  fi

  local home_dir="${HOME_DIR_HOST:-$SANDBOXES_BASE/$env}"
  # Tolerate a pre-existing home dir -- that is how an old ad-hoc sandbox home
  # gets adopted as an environment.
  mkdir -p "$home_dir/bin" "$home_dir/.ssh"
  chmod 700 "$home_dir" "$home_dir/.ssh"

  local key="$home_dir/.ssh/id_ed25519"
  if [[ -e "$key" ]]; then
    echo "SSH key already present: $key"
  else
    # Comment carries the env name, not an email: the key identifies the
    # sandbox, and the private key never leaves your machines.
    ssh-keygen -t ed25519 -N "" -f "$key" -C "${env}-sandbox"
    echo
    echo "Protecting the key with a passphrase is recommended (it lives in the env home):"
    echo "  ssh-keygen -p -f $key"
  fi

  mkdir -p "$CONF_DIR"
  cat > "$conf" <<EOF
# sandbox environment: ${env}   (sourced by sandbox.sh -- plain bash)
#
# The \${VAR:-...} form keeps one-off command-line overrides working
# (e.g. IMAGE=test sandbox.sh ${env}). Use a plain VAR=... to hard-pin.
#
#IMAGE="\${IMAGE:-sandbox:latest}"
#HOME_DIR_HOST="\${HOME_DIR_HOST:-\$SANDBOXES_BASE/${env}}"
#WORK_DIR_HOST="\${WORK_DIR_HOST:-\$PWD}"        # pin a project dir here if desired
#HOSTNAME_VALUE="\${HOSTNAME_VALUE:-${env}}"
#CONTAINER_HOME="\${CONTAINER_HOME:-/home/u}"
#
# Opt-out of Azure isolation: share the HOST az login with this environment.
# Off by default -- each environment normally gets its own 'az login'.
#AZURE_DIR_HOST="\${AZURE_DIR_HOST:-\$HOME/.azure}"
#
# Extra bind mounts, HOST:CONTAINER (":Z" appended) or HOST:CONTAINER:opts.
# For credentials rewritten in place (kubelogin etc.) mount the directory,
# not the file -- atomic renames break single-file mounts.
#EXTRA_MOUNTS=("\$HOME/proj/<customer>/kubeconfig:/home/u/.kube/config:ro,Z")
#
# Command to run when none is given on the CLI (default: the image's bash -l).
# (zellij: name the session after the env instead of a random name)
#DEFAULT_CMD=(zellij attach --create "\$ENV_NAME")
EOF

  echo
  echo "Environment '$env' created."
  echo "  home: $home_dir"
  echo "  conf: $conf"
  echo
  echo "Public key (register it with the customer's Git server / Azure DevOps):"
  cat "$key.pub"
  echo
  echo "Next steps:"
  echo "  ${SCRIPT_NAME} $env             # start a shell in the sandbox"
  echo "  az login                        # inside: per-environment Azure login"
  echo "  claude                          # inside: per-environment Claude login"
}

if [[ $# -eq 0 ]]; then
  usage >&2
  exit 1
fi

case "$1" in
  -h|--help|help)
    usage
    exit 0
    ;;
  list)
    list_envs
    exit 0
    ;;
  init)
    if [[ $# -ne 2 ]]; then
      echo "Usage: ${SCRIPT_NAME} init <env>" >&2
      exit 1
    fi
    cmd_init "$2"
    exit 0
    ;;
esac

ENV_NAME="$1"
shift
validate_env_name "$ENV_NAME"

CONF_FILE="$CONF_DIR/$ENV_NAME.conf"
if [[ ! -f "$CONF_FILE" ]]; then
  echo "[ERROR] No such environment '$ENV_NAME' ($CONF_FILE not found)." >&2
  echo "        Create it with: ${SCRIPT_NAME} init $ENV_NAME" >&2
  echo >&2
  list_envs >&2
  exit 1
fi
# shellcheck disable=SC1090
source "$CONF_FILE"

# Derived defaults -- applied after the conf so a conf can override them, while
# the ${VAR:-...} form in the conf keeps command-line overrides winning.
IMAGE="${IMAGE:-sandbox:latest}"
CONTAINER_HOME="${CONTAINER_HOME:-/home/u}"
HOSTNAME_VALUE="${HOSTNAME_VALUE:-$ENV_NAME}"
BASE_NAME="${NAME:-$ENV_NAME}"
NAME="${BASE_NAME}-$(date +%Y%m%d-%H%M%S)"
HOME_DIR_HOST="${HOME_DIR_HOST:-$SANDBOXES_BASE/$ENV_NAME}"
# Empty by default: no nested .azure mount, the environment's own
# $HOME_DIR_HOST/.azure is used. A conf may set it to share a host login.
AZURE_DIR_HOST="${AZURE_DIR_HOST:-}"

if [[ ! -d "$HOME_DIR_HOST" ]]; then
  echo "[ERROR] Home directory for '$ENV_NAME' is missing: $HOME_DIR_HOST" >&2
  echo "        Create it with: ${SCRIPT_NAME} init $ENV_NAME" >&2
  exit 1
fi

# Mount the directory you run this script from into the container (workspace).
# Refuse a /work that would expose the whole home, the env confs (executed on
# the host!) or the other environments' homes to the container.
path_within() {
  case "$1" in "$2"|"$2"/*) return 0 ;; *) return 1 ;; esac
}

WORK_DIR_HOST="${WORK_DIR_HOST:-$PWD}"
work_real="$(realpath "$WORK_DIR_HOST")"
if [[ "$work_real" == "$(realpath "$HOME")" ]]; then
  echo "[WARNING] Not mounting entire home directory as /work. Proceeding without /work mount."
  MOUNT_WORK=false
elif path_within "$(realpath "$CONF_DIR")" "$work_real" \
  || path_within "$(realpath "$SANDBOXES_BASE")" "$work_real"; then
  echo "[WARNING] ${WORK_DIR_HOST} contains the sandbox base/conf dir. Proceeding without /work mount."
  MOUNT_WORK=false
else
  MOUNT_WORK=true
fi

args=(
  run
  --hostname "${HOSTNAME_VALUE}"
  --name "${NAME}"
  -it
  --rm
  --userns=keep-id
  -e "HOME=${CONTAINER_HOME}"
  -e "CLAUDE_CONFIG_DIR=${CONTAINER_HOME}/.claude"
  -v "${HOME_DIR_HOST}:${CONTAINER_HOME}:Z"
)

# Optional nested mount over ~/.azure (opt-out of per-environment isolation).
# Pre-create the mountpoint so it is owned by us rather than by a
# user-namespace-mapped uid that podman would invent.
if [[ -n "${AZURE_DIR_HOST}" ]]; then
  mkdir -p "${HOME_DIR_HOST}/.azure"
  args+=(-v "${AZURE_DIR_HOST}:${CONTAINER_HOME}/.azure:Z")
fi

# Extra mounts declared in the env conf, e.g. a specific kubeconfig:
#   EXTRA_MOUNTS=("$HOME/proj/acme/kubeconfig:/home/u/.kube/config")
# Entries are HOST:CONTAINER (":Z" appended) or HOST:CONTAINER:opts (as-is).
if [[ -n "${EXTRA_MOUNTS+x}" ]]; then
  for mount in "${EXTRA_MOUNTS[@]}"; do
    src="${mount%%:*}"
    rest="${mount#*:}"
    dst="${rest%%:*}"
    if [[ "$src" == "$mount" || -z "$src" || -z "$dst" ]]; then
      echo "[ERROR] Invalid EXTRA_MOUNTS entry '$mount' (expected HOST:CONTAINER[:opts])." >&2
      exit 1
    fi
    if [[ ! -e "$src" ]]; then
      echo "[ERROR] EXTRA_MOUNTS source does not exist: $src" >&2
      exit 1
    fi
    [[ "$rest" == "$dst" ]] && mount="${mount}:Z"
    # Pre-create mountpoints nested in the home so they stay owned by us
    # rather than by a user-namespace-mapped uid that podman would invent.
    if [[ "$dst" == "$CONTAINER_HOME"/* ]]; then
      mountpoint="${HOME_DIR_HOST}/${dst#"$CONTAINER_HOME"/}"
      if [[ -d "$src" ]]; then
        mkdir -p "$mountpoint"
      else
        mkdir -p "$(dirname "$mountpoint")"
        touch "$mountpoint"
      fi
    fi
    args+=(-v "$mount")
  done
fi

# Only mount /work if not running from $HOME
if [[ "${MOUNT_WORK}" == true ]]; then
  args+=(-v "${WORK_DIR_HOST}:/work:Z")
fi

# The image must stay last; anything after it is passed to the container.
args+=("${IMAGE}")

# With no command on the CLI, fall back to the conf's DEFAULT_CMD (e.g. zellij)
# instead of the image default (bash -l). An explicit CLI command always wins.
if [[ $# -eq 0 && -n "${DEFAULT_CMD+x}" ]]; then
  set -- "${DEFAULT_CMD[@]}"
fi

exec podman "${args[@]}" "$@"
