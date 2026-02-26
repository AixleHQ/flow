#!/usr/bin/env bash
set -euo pipefail

ARCH=$(uname -m)
case "$ARCH" in
  x86_64) ARCH=amd64 ;;
  aarch64|arm64) ARCH=arm64 ;;
  *)
    echo "Unsupported architecture: ${ARCH}" >&2
    exit 1
    ;;
esac

OS=linux

# docker cli
apk add --no-cache docker docker-cli-compose

# kubectl
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
chmod +x /usr/local/bin/kubectl

# helm
HELM_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" https://api.github.com/repos/helm/helm/releases/latest | sed -n 's/.*"tag_name": "\(v[^\"]*\)".*/\1/p')
if [[ -z "$HELM_VERSION" ]]; then
  echo "Warning: Failed to resolve Helm version from GitHub API, using fallback" >&2
  HELM_VERSION="v3.17.1"
fi
curl -L -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
tar -xzf /tmp/helm.tgz -C /tmp
mv "/tmp/${OS}-${ARCH}/helm" /usr/local/bin/helm
chmod +x /usr/local/bin/helm
rm -rf /tmp/helm.tgz "/tmp/${OS}-${ARCH}"

# minikube
curl -L -o /usr/local/bin/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-${OS}-${ARCH}"
chmod +x /usr/local/bin/minikube

# aws cli
apk add --no-cache python3 py3-pip groff
pip3 install --no-cache-dir --break-system-packages awscli

# aws-vault
AWS_VAULT_VERSION=$(curl -sL -H "Accept: application/vnd.github+json" https://api.github.com/repos/99designs/aws-vault/releases/latest | sed -n 's/.*"tag_name": "\(v[^\"]*\)".*/\1/p')
if [[ -z "$AWS_VAULT_VERSION" ]]; then
  echo "Warning: Failed to resolve aws-vault version from GitHub API, using fallback" >&2
  AWS_VAULT_VERSION="v7.2.0"
fi
curl -L -o /usr/local/bin/aws-vault "https://github.com/99designs/aws-vault/releases/download/${AWS_VAULT_VERSION}/aws-vault-${OS}-${ARCH}"
chmod +x /usr/local/bin/aws-vault

echo "Installed kubectl $(kubectl version --client -o yaml | head -5)"
echo "Installed helm $(helm version --template '{{.Version}}')"
echo "Installed minikube $(minikube version --short)"
echo "Installed docker $(docker --version)"
echo "Installed docker-compose $(docker-compose --version)"
echo "Installed aws-cli $(aws --version)"
echo "Installed aws-vault $(aws-vault --version)"
