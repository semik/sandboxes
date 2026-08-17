#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-terraform-az:latest}"

if [[ "$PWD" == "$HOME" ]]; then
  echo "[WARNING] Not mounting entire home directory as /work. Proceeding without /work mount."
  MOUNT_WORK=false
else
  WORK_DIR_HOST="${WORK_DIR_HOST:-$PWD}"
  MOUNT_WORK=true
fi
BASE_NAME="${NAME:-azure-env}"
RUN_TIMESTAMP=$(date +%Y%m%d-%H%M%S)
NAME="${BASE_NAME}-${RUN_TIMESTAMP}"
HOSTNAME_VALUE="${HOSTNAME_VALUE:-azure-env}"

CONTAINER_HOME="${CONTAINER_HOME:-/home/ubuntu}"

# Persistent sandbox "home" (mounted to /home/ubuntu in the container).
# By default, keep your existing host sandbox dir if it exists.
DEFAULT_HOME_HOST="${HOME}/Sync/3K/azure-env"
if [[ -d "${DEFAULT_HOME_HOST}" ]]; then
  HOME_DIR_HOST_DEFAULTED="${DEFAULT_HOME_HOST}"
else
  HOME_DIR_HOST_DEFAULTED="${PWD}"
fi
HOME_DIR_HOST="${HOME_DIR_HOST:-${HOME_DIR_HOST_DEFAULTED}}"

# Mount the directory you run this script from into the container (workspace).
WORK_DIR_HOST="${WORK_DIR_HOST:-$PWD}"

# Pass your host Azure CLI auth into the container (optional).
AZURE_DIR_HOST="${AZURE_DIR_HOST:-${HOME}/.azure}"

# Persistent Claude Code config. Deliberately NOT under ~/Sync -- that is a
# Syncthing folder, and .credentials.json holds a long-lived OAuth token.
# CLAUDE_CONFIG_DIR (set below) also pulls ~/.claude.json into this directory;
# without it that file would land in the synced sandbox home instead.
CLAUDE_DIR_HOST="${CLAUDE_DIR_HOST:-${HOME}/.local/share/azure-env-claude}"
mkdir -p "${CLAUDE_DIR_HOST}"

# Pre-create the nested mountpoints inside the sandbox home. They stay empty --
# the bind mounts above cover them -- but creating them here keeps them owned by
# us rather than by a user-namespace-mapped uid that podman would invent.
mkdir -p "${HOME_DIR_HOST}/.claude" "${HOME_DIR_HOST}/.azure"

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
  -v "${AZURE_DIR_HOST}:${CONTAINER_HOME}/.azure:Z"
  -v "${CLAUDE_DIR_HOST}:${CONTAINER_HOME}/.claude:Z"
)

# Only mount /work if not running from $HOME
if [[ "${MOUNT_WORK}" == true ]]; then
  args+=(-v "${WORK_DIR_HOST}:/work:Z")
fi

# The image must stay last; anything after it is passed to the container.
args+=("${IMAGE}")

exec podman "${args[@]}" "$@"
