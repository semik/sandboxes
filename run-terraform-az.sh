#!/usr/bin/env bash
set -euo pipefail

IMAGE="${IMAGE:-terraform-az:latest}"
NAME="${NAME:-azure-env}"
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

args=(
  run
  --hostname "${HOSTNAME_VALUE}"
  --name "${NAME}"
  -it
  --rm
  --userns=keep-id
  -e "HOME=${CONTAINER_HOME}"
  -v "${HOME_DIR_HOST}:${CONTAINER_HOME}:Z"
  -v "${WORK_DIR_HOST}:/work:Z"
  -v "${AZURE_DIR_HOST}:${CONTAINER_HOME}/.azure:Z"
  -w /work
  "${IMAGE}"
)

if [[ $# -gt 0 ]]; then
  exec podman "${args[@]}" "$@"
else
  exec podman "${args[@]}"
fi
