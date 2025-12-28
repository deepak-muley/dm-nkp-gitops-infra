# Harbor on NKP - Management Cluster Deployment

Harbor is now deployed on the management cluster only.

## Documentation Links

- https://portal.nutanix.com/page/documents/details?targetId=Nutanix-Kubernetes-Platform-v2_16:top-deploy-integrated-private-registry-on-mgmt-cluster-t.html

- https://portal.nutanix.com/page/documents/details?targetId=Nutanix-Kubernetes-Platform-v2_16:top-use-integrated-private-registry-on-nkp-cluster-t.html

- https://portal.nutanix.com/page/documents/details?targetId=Nutanix-Kubernetes-Platform-v2_16:top-configure-TLS-certificate-t.html

## Get Harbor Registry URL

Harbor is installed on the management cluster:

```bash
echo "https://$(kubectl -n kommander get kommandercluster host-cluster -o jsonpath='{.status.ingress.address}'):5000"
```

## How to Get Harbor Secret

```bash
kubectl get secrets -n ncr-system harbor-admin-password -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d
```

## Configure Docker with Certificate

```bash
# Get Harbor address
HARBOR_ADDRESS=$(kubectl -n kommander get kommandercluster host-cluster -o jsonpath='{.status.ingress.address}')

# Create directory if it doesn't exist
sudo mkdir -p /etc/docker/certs.d/${HARBOR_ADDRESS}:5000

# Add certificate to registry-specific location
kubectl -n kommander get kommandercluster host-cluster -o jsonpath='{.status.ingress.caBundle}' | base64 -d | sudo tee /etc/docker/certs.d/${HARBOR_ADDRESS}:5000/ca.crt > /dev/null

# Also add to global location (fallback)
sudo mkdir -p /etc/docker/certs.d
kubectl -n kommander get kommandercluster host-cluster -o jsonpath='{.status.ingress.caBundle}' | base64 -d | sudo tee /etc/docker/certs.d/ca.crt > /dev/null

# Set proper permissions
sudo chmod 644 /etc/docker/certs.d/${HARBOR_ADDRESS}:5000/ca.crt
sudo chmod 644 /etc/docker/certs.d/ca.crt

# Restart Docker daemon (if running as systemd service)
sudo systemctl restart docker

# Or if using containerd/dockerd directly, restart the service
# sudo systemctl restart containerd
```

## Troubleshooting Docker Certificate Issues

If you get `x509: certificate signed by unknown authority` error:

1. **Verify certificate was added correctly:**
```bash
# Check if certificate file exists and has content
sudo cat /etc/docker/certs.d/10.23.130.72:5000/ca.crt

# Verify certificate format (should show certificate details)
openssl x509 -in /etc/docker/certs.d/10.23.130.72:5000/ca.crt -text -noout
```

2. **Restart Docker daemon:**
```bash
# For systemd
sudo systemctl restart docker

# Or restart containerd if using containerd
sudo systemctl restart containerd
```

3. **Verify Docker can read the certificate:**
```bash
# Test Docker login first (required before push)
HARBOR_ADDRESS="10.23.130.72"
HARBOR_PASSWORD=$(kubectl get secrets -n ncr-system harbor-admin-password -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)
docker login ${HARBOR_ADDRESS}:5000 -u admin -p ${HARBOR_PASSWORD}
```

4. **If still failing, try insecure registry (NOT RECOMMENDED for production):**
```bash
# Add to /etc/docker/daemon.json (create if doesn't exist)
sudo mkdir -p /etc/docker
echo '{"insecure-registries": ["10.23.130.72:5000"]}' | sudo tee /etc/docker/daemon.json
sudo systemctl restart docker
```

5. **If Docker push hangs or is slow:**
```bash
# Check if you're logged in
cat ~/.docker/config.json | grep -A 2 "10.23.130.72:5000"

# If not logged in, login first
HARBOR_PASSWORD=$(kubectl get secrets -n ncr-system harbor-admin-password -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)
docker login 10.23.130.72:5000 -u admin -p ${HARBOR_PASSWORD}

# Check Harbor pod status (on the management cluster)
kubectl get pods -n ncr-system | grep harbor

# Check Harbor logs for errors
kubectl logs -n ncr-system -l app=harbor --tail=50

# Try with verbose output to see where it's hanging
DOCKER_BUILDKIT=0 docker push 10.23.130.72:5000/library/alpine

# Check network connectivity with timeout
timeout 10 curl -k https://10.23.130.72:5000/v2/

# If push hangs, cancel (Ctrl+C) and check:
# - Harbor storage quota
# - Network connectivity
# - Harbor registry service status
```

6. **Alternative: Use HTTP instead of HTTPS (if Harbor allows):**
```bash
# Try pushing to http:// instead of https://
docker push http://10.23.130.72:5000/library/alpine
```

## Test Push Image

```bash
# Get Harbor address and credentials
HARBOR_ADDRESS=$(kubectl -n kommander get kommandercluster host-cluster -o jsonpath='{.status.ingress.address}')
HARBOR_PASSWORD=$(kubectl get secrets -n ncr-system harbor-admin-password -o jsonpath='{.data.HARBOR_ADMIN_PASSWORD}' | base64 -d)

# Login to Harbor (REQUIRED before push)
docker login ${HARBOR_ADDRESS}:5000 -u admin -p ${HARBOR_PASSWORD}

# Pull, tag, and push image
docker pull alpine
docker tag alpine ${HARBOR_ADDRESS}:5000/library/alpine
docker push ${HARBOR_ADDRESS}:5000/library/alpine
```

