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
apk add --no-cache docker-cli docker-compose

# kubectl
KUBECTL_VERSION=$(curl -L -s https://dl.k8s.io/release/stable.txt)
curl -L -o /usr/local/bin/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/${OS}/${ARCH}/kubectl"
chmod +x /usr/local/bin/kubectl

# helm
HELM_VERSION=$(curl -s https://api.github.com/repos/helm/helm/releases/latest | sed -n 's/.*"tag_name": "\(v[^\"]*\)".*/\1/p')
if [[ -z "$HELM_VERSION" ]]; then
  echo "Failed to resolve Helm version" >&2
  exit 1
fi
curl -L -o /tmp/helm.tgz "https://get.helm.sh/helm-${HELM_VERSION}-${OS}-${ARCH}.tar.gz"
tar -xzf /tmp/helm.tgz -C /tmp
mv "/tmp/${OS}-${ARCH}/helm" /usr/local/bin/helm
chmod +x /usr/local/bin/helm
rm -rf /tmp/helm.tgz "/tmp/${OS}-${ARCH}"

# minikube
curl -L -o /usr/local/bin/minikube "https://storage.googleapis.com/minikube/releases/latest/minikube-${OS}-${ARCH}"
chmod +x /usr/local/bin/minikube

echo "Installed kubectl $(kubectl version --client --short), helm $(helm version --short), minikube $(minikube version --short)"
echo "Installed docker $(docker --version)"
echo "Installed docker-compose $(docker-compose --version)"
