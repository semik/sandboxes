# Sandboxes

## terraform-az container

Is designed for Terraform development with Azure. It includes the Azure CLI (`az`), Terraform, Kubernetes tools (`kubectl`, `helm`, `kubelogin`), and k9s for Kubernetes cluster management.

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
	-v "$HOME/Sync/3K/azure-env:/home/ubuntu:Z" \
	-v "$PWD:/work:Z" \
	-v "$HOME/.azure:/home/ubuntu/.azure:Z" \
	-w /work \
	terraform-az:latest
```

Notes:

## Included tools

- Azure CLI (`az`)
- Terraform
- Kubernetes CLI (`kubectl`)
- Helm
- kubelogin
- k9s (Kubernetes cluster management)

## Using k9s

To launch k9s in the container:

```bash
./run-terraform-az.sh k9s
```

Or interactively:

```bash
podman run ... terraform-az:latest k9s
```
- The image default command is `bash -l` so bash-completion loads.

Included CLIs:
- `az`, `kubectl`, `helm`, `kubelogin`

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