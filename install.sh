#!/usr/bin/env bash
set -ev

export LC_ALL=C.UTF-8

BASEDIR="$(dirname "$0")"

if [ -z "${GATEWAY_DOMAIN}" ]; then
  echo "The domain name for the gateway is required, if you do not have a domain name press enter to use the default"
  read -rp "Enter the domain name for the gateway [cluster.local]: " GATEWAY_DOMAIN
  export GATEWAY_DOMAIN="${GATEWAY_DOMAIN:-cluster.local}"
fi

function replace_tld_and_copy() {
    find "$1" -type d -exec mkdir -p /etc/genestack/{} \;
    find "$1" -type f -exec sh -c "cat {} | sed 's|your.domain.tld|${GATEWAY_DOMAIN}|g' > /etc/genestack/{}" \;
}

pushd "${BASEDIR}" || error "Could not change to ${BASEDIR}"
    if [ ! -d /etc/genestack/kustomize/ ]; then
        echo "The /etc/genestack/kustomize/ directory does not exist"
        exit 99
    elif [ ! -d /etc/genestack/gateway-api/ ]; then
        echo "The /etc/genestack/gateway-api/ directory does not exist"
        exit 99
    elif [ ! -d /etc/genestack/helm-configs/ ]; then
        echo "The /etc/genestack/helm-configs/ directory does not exist"
        exit 99
    fi

    replace_tld_and_copy kustomize/
    replace_tld_and_copy gateway-api/
    replace_tld_and_copy helm-configs/

popd || error "Could not change to previous directory"

kubectl apply -f /etc/genestack/kustomize/element/base/namespace.yaml

helm upgrade --install \
             --namespace "ess" \
             ess oci://ghcr.io/element-hq/ess-helm/matrix-stack \
             -f /etc/genestack/helm-configs/element/hostnames.yaml \
             --post-renderer /etc/genestack/kustomize/kustomize.sh \
             --post-renderer-args element/base

kubectl apply -f /etc/genestack/gateway-api/routes/custom-element-gateway-route.yaml

if ! kubectl -n envoy-gateway get gateway flex-gateway -o yaml | grep "chat.${GATEWAY_DOMAIN}"; then
    kubectl patch -n envoy-gateway gateway flex-gateway \
                  --type='json' \
                  --patch="$(jq -s 'flatten | .' /etc/genestack/gateway-api/listeners/element-https.json)"
fi
