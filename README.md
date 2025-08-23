# Genestack Apps – Element (ESS)

This repository provides the configuration used to deploy the Element Server Suite (Matrix stack) on Kubernetes, wired behind Envoy Gateway via Gateway API. The `install.sh` script performs placeholder replacement, copies configs into `/etc/genestack`, installs/updates the Helm release, applies Gateway API routes, and patches the Envoy Gateway if needed.

## Prerequisites

- Kubernetes cluster with kubectl access (current context points to the target cluster)

- Helm v3 with OCI support (Helm 3.9+ recommended)

- jq installed on the machine running the script

- Envoy Gateway and Gateway API CRDs installed; a Gateway named `flex-gateway` exists in the `envoy-gateway` namespace

- The following directories exist on the target host and are writable:

  - `/etc/genestack/kustomize/` (must contain `/etc/genestack/kustomize/kustomize.sh` post-renderer script)

  - `/etc/genestack/gateway-api/`

  - `/etc/genestack/helm-configs/`

If any of these directories are missing, the installer exits with code 99.

## Configuration

The installer needs the external domain used by the gateway. Provide it via the `GATEWAY_DOMAIN` environment variable, or you will be prompted. If you press Enter at the prompt, the default `cluster.local` will be used.

- Placeholder replacement: All files in this repository under `kustomize/`, `gateway-api/`, and `helm-configs/` that contain `your.domain.tld` will be rendered with your chosen domain and written into a mirrored path under `/etc/genestack/…`.

Examples:

``` bash
# Option A: Provide domain via environment variable
export GATEWAY_DOMAIN=example.com

# Option B: Run and respond to the prompt (default: cluster.local)
./install.sh
```

## Install

Run the installer from the repository root:

``` bash
chmod +x ./install.sh

# With an explicit domain
GATEWAY_DOMAIN=example.com ./install.sh

# Or interactively (press Enter to accept cluster.local)
./install.sh
```

What the script does:

1. Validates required target directories exist under `/etc/genestack/`.

2. Replaces `your.domain.tld` with `$GATEWAY_DOMAIN` in repo files and writes them to `/etc/genestack/<same relative path>`.

3. Installs/updates the Helm release for ESS:

    - Release name: `ess`

    - Namespace: `ess`

    - Chart: `oci://ghcr.io/element-hq/ess-helm/matrix-stack`

    - Values: `/etc/genestack/helm-configs/element/hostnames.yaml`

    - Post-renderer: `/etc/genestack/kustomize/kustomize.sh` with args `element/base`

    - Blocks until resources are ready (`--wait`)

4. Applies the Gateway API route:

    - `/etc/genestack/gateway-api/routes/custom-element-gateway-route.yaml`

5. Patches the `envoy-gateway/flex-gateway` resource if it does not already reference `chat.ess.$GATEWAY_DOMAIN` by applying JSON patches found in:

    - `/etc/genestack/gateway-api/listeners/element-https.json` (flattened via `jq -s 'flatten | .'`)

## Verify

After the installer completes, verify key resources:

``` bash
# ESS workloads
kubectl get pods -n ess

# Gateway should reference your domain host
kubectl -n envoy-gateway get gateway flex-gateway -o yaml | grep "chat.ess.${GATEWAY_DOMAIN:-example.com}"

# Routes
kubectl get httproutes.gateway.networking.k8s.io -A
```

Confirm DNS for your chosen domain points to the Envoy data plane so hosts like `chat.ess.<your-domain>` resolve and route correctly.

## Troubleshooting

- Missing /etc directories: Create the required `/etc/genestack/...` directories and ensure `/etc/genestack/kustomize/kustomize.sh` exists and is executable. This should already exist in an environment where Genestack has been deployed. Find out more about Genestack [here](https://github.com/rackerlabs/genestack).

- Helm OCI errors: Use a Helm version with OCI support; ensure outbound access to `ghcr.io`.

- jq not found: Install it (for macOS: `brew install jq`, for Debian: `apt-get install jq`).

- Gateway not patched: Ensure `envoy-gateway` namespace exists and `flex-gateway` is present; re-run the installer after fixing.

## Uninstall

``` bash
# Remove the Helm release
helm uninstall ess -n ess

# Remove the route applied by the installer
kubectl delete -f /etc/genestack/gateway-api/routes/custom-element-gateway-route.yaml
```

Note: If you manually changed the `flex-gateway` listeners, you may want to revert those changes according to your environment’s baseline.
