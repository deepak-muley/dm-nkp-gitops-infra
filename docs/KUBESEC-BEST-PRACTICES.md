# KubeSec Best Practices - Security Rationale

This document explains the security rationale behind KubeSec recommendations and why they matter for securing Kubernetes workloads.

## Table of Contents

1. [High UID/GID (>10000)](#high-uidgid-10000)
2. [Host Users Disabled (hostUsers: false)](#host-users-disabled-hostusers-false)
3. [Run As Non-Root](#run-as-non-root)
4. [Read-Only Root Filesystem](#read-only-root-filesystem)
5. [Drop All Capabilities](#drop-all-capabilities)
6. [Service Account Token Automount Disabled](#service-account-token-automount-disabled)
7. [Resource Requests and Limits](#resource-requests-and-limits)
8. [Health Probes](#health-probes)
9. [Seccomp Profiles](#seccomp-profiles)
10. [Image Digests](#image-digests)

---

## High UID/GID (>10000)

### Recommendation
Use `runAsUser` and `runAsGroup` values greater than 10000 (e.g., 10001, 65534).

### Why This Matters

**The Problem:**
Traditional Linux systems assign UIDs/GIDs in ranges:
- **0-99**: System accounts (root=0, daemon=1, etc.)
- **100-999**: System services and applications
- **1000-65533**: Regular user accounts (typically start at 1000)
- **65534**: Traditionally "nobody" user

When containers run with low UIDs (like 1000), they may conflict with host system users, creating security risks.

**Security Risks:**

1. **UID/GID Collision Attacks**
   - If a container runs as UID 1000 and the host also has a user with UID 1000, they share the same identity
   - Files owned by UID 1000 on the host may be accessible to the container
   - This can lead to privilege escalation if the container escapes

2. **Volume Mount Conflicts**
   - When mounting volumes from the host, file ownership is based on UIDs
   - A container with UID 1000 could access files owned by host user 1000
   - High UIDs (>10000) are unlikely to exist on the host, reducing collision risk

3. **Host Filesystem Access**
   - In container escape scenarios, the attacker inherits the container's UID
   - If that UID matches a host user, they may have unexpected permissions
   - High UIDs minimize this risk since they're unlikely to have privileges on the host

**Best Practice Example:**
```yaml
securityContext:
  runAsUser: 10001    # High UID, unlikely to conflict with host users
  runAsGroup: 10001   # High GID, unlikely to conflict with host groups
  fsGroup: 10001      # Files created in volumes will have this GID
```

**References:**
- [Kubernetes Security Context - runAsUser](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/#set-the-security-context-for-a-pod)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.1_20220415.PDF)

---

## Host Users Disabled (hostUsers: false)

### Recommendation
Set `hostUsers: false` in the pod's `securityContext` to enable user namespace isolation (Kubernetes 1.25+).

### Why This Matters

**The Problem:**
By default, containers use the same user namespace as the host. This means:
- Container UIDs map directly to host UIDs
- A container running as UID 1000 is actually UID 1000 on the host
- Container escape scenarios inherit the host UID

**The Solution:**
User namespaces provide UID/GID remapping:
- Container UIDs are mapped to different UIDs on the host
- Container UID 0 (root) might map to host UID 65534 (nobody)
- Even if a container runs as root, it appears as a non-root user on the host

**Security Benefits:**

1. **Reduced Privilege Escalation Risk**
   - Container root (UID 0) doesn't map to host root
   - Container escapes are less likely to gain host privileges
   - Defense-in-depth: multiple layers of isolation

2. **UID/GID Collision Prevention**
   - User namespace remapping prevents collisions
   - Container UID 1000 and host UID 1000 are isolated
   - Each namespace has its own UID/GID mapping

3. **Improved Container Isolation**
   - Additional isolation layer beyond cgroups and namespaces
   - Reduces the impact of container escapes
   - Critical for multi-tenant environments

**Requirements:**
- Kubernetes 1.25+
- Container runtime support (containerd, CRI-O with user namespace support)
- Feature gate enabled on the cluster

**Best Practice Example:**
```yaml
securityContext:
  hostUsers: false  # Enable user namespace isolation
  runAsUser: 10001
  runAsGroup: 10001
```

**Limitations:**
- Not all validation tools recognize this field yet (KubeSec schema may not validate it)
- Requires cluster and runtime support
- Some features may not work with user namespaces (e.g., some storage drivers)

**References:**
- [Kubernetes User Namespaces](https://kubernetes.io/docs/concepts/security/pod-security-standards/#user-namespaces)
- [Kubernetes Enhancement Proposal - User Namespaces](https://github.com/kubernetes/enhancements/tree/master/keps/sig-node/127-user-namespaces)

---

## Run As Non-Root

### Recommendation
Always set `runAsNonRoot: true` and specify a non-root `runAsUser`.

### Why This Matters

**The Problem:**
Running containers as root (UID 0) grants maximum privileges:
- Root can modify system files
- Root can install malicious software
- Root can access sensitive data
- Container escapes become more dangerous

**Security Risks:**

1. **Privilege Escalation**
   - Root in container = maximum container privileges
   - Increases risk if container escape occurs
   - Attackers gain more control

2. **File System Access**
   - Root can read/write any file in the container
   - Can modify application binaries
   - Can tamper with configuration files

3. **Host Impact**
   - Even with user namespaces, root containers are riskier
   - More likely to find privilege escalation paths
   - Defense-in-depth: avoid root when possible

**Best Practice Example:**
```yaml
securityContext:
  runAsNonRoot: true
  runAsUser: 10001    # Non-root user
  runAsGroup: 10001
```

**References:**
- [Kubernetes Pod Security Standards - Restricted Profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- [CIS Kubernetes Benchmark - 5.7.3](https://www.cisecurity.org/benchmark/kubernetes)

---

## Read-Only Root Filesystem

### Recommendation
Set `readOnlyRootFilesystem: true` and mount writable volumes for temporary files.

### Why This Matters

**The Problem:**
Writable root filesystems allow attackers to:
- Modify application binaries
- Install malware
- Tamper with configuration files
- Create backdoors

**Security Benefits:**

1. **Immutable Application Code**
   - Application binaries cannot be modified
   - Prevents malware installation
   - Reduces attack surface

2. **Configuration Protection**
   - Configuration files remain unchanged
   - Prevents attackers from changing behavior
   - Maintains integrity

3. **Immutable Root**
   - Root filesystem is protected
   - Attackers cannot persist changes
   - Reduces persistence mechanisms

**Implementation:**
```yaml
securityContext:
  readOnlyRootFilesystem: true
containers:
  - name: app
    volumeMounts:
      - name: tmp
        mountPath: /tmp      # Writable volume for temporary files
      - name: var-run
        mountPath: /var/run  # Writable volume for runtime files
volumes:
  - name: tmp
    emptyDir: {}
  - name: var-run
    emptyDir: {}
```

**References:**
- [Kubernetes Pod Security Standards - Restricted Profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)
- [NSA Kubernetes Hardening Guide - Read-Only Root Filesystem](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.1_20220415.PDF)

---

## Drop All Capabilities

### Recommendation
Drop all Linux capabilities and add only those explicitly required: `capabilities.drop: ["ALL"]`.

### Why This Matters

**The Problem:**
Containers inherit default Linux capabilities that may not be needed:
- `NET_RAW`: Can create raw sockets (used in some attacks)
- `SYS_ADMIN`: Can perform administrative operations
- `DAC_OVERRIDE`: Can bypass file permission checks
- Many others that increase attack surface

**Security Benefits:**

1. **Minimal Privileges**
   - Principle of least privilege
   - Only grant capabilities that are actually needed
   - Reduces attack surface significantly

2. **Capability-Based Attacks**
   - Attackers cannot use dropped capabilities
   - Reduces available attack vectors
   - Makes exploitation harder

3. **Defense in Depth**
   - Even if container escape occurs, capabilities are limited
   - Multiple layers of security controls
   - Reduces impact of compromises

**Best Practice Example:**
```yaml
securityContext:
  capabilities:
    drop:
      - ALL          # Drop all capabilities first
    add:              # Then add only what's needed (if anything)
      - NET_BIND_SERVICE  # Example: bind to ports < 1024
```

**Common Capabilities:**
- `NET_BIND_SERVICE`: Bind to privileged ports (< 1024)
- `CHOWN`: Change file ownership (usually not needed)
- `SETUID`, `SETGID`: Change process UID/GID (usually not needed)

**References:**
- [Linux Capabilities](https://man7.org/linux/man-pages/man7/capabilities.7.html)
- [Kubernetes Pod Security Standards - Restricted Profile](https://kubernetes.io/docs/concepts/security/pod-security-standards/#restricted)

---

## Service Account Token Automount Disabled

### Recommendation
Set `automountServiceAccountToken: false` unless the pod explicitly needs Kubernetes API access.

### Why This Matters

**The Problem:**
By default, Kubernetes automatically mounts a service account token in every pod at `/var/run/secrets/kubernetes.io/serviceaccount/token`. This token:
- Provides access to the Kubernetes API
- Inherits permissions from the ServiceAccount's RBAC
- Can be stolen by attackers who compromise the container

**Security Risks:**

1. **Token Theft**
   - If container is compromised, token can be exfiltrated
   - Attacker gains Kubernetes API access
   - Can create/manage resources based on ServiceAccount permissions

2. **Lateral Movement**
   - Stolen tokens can be used to access other resources
   - Attacker can escalate privileges within the cluster
   - Can deploy malicious workloads

3. **Unnecessary Exposure**
   - Most pods don't need Kubernetes API access
   - Mounting tokens by default violates least privilege
   - Increases attack surface unnecessarily

**Best Practice Example:**
```yaml
spec:
  automountServiceAccountToken: false  # Disable automatic mounting
  serviceAccountName: my-app-sa        # Use non-default ServiceAccount
```

**When to Enable:**
- Pods that need to interact with Kubernetes API (operators, controllers)
- Use specific ServiceAccounts with minimal required permissions
- Enable only when absolutely necessary

**References:**
- [Kubernetes Service Accounts](https://kubernetes.io/docs/concepts/security/service-accounts/)
- [NSA Kubernetes Hardening Guide - Service Account Tokens](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.1_20220415.PDF)

---

## Resource Requests and Limits

### Recommendation
Always specify `requests` and `limits` for CPU and memory for all containers.

### Why This Matters

**The Problem:**
Without resource constraints:
- Containers can consume all available cluster resources
- One misbehaving pod can starve other workloads
- Cluster becomes unstable and unpredictable
- Denial of Service (DoS) attacks are easier

**Security and Stability Benefits:**

1. **Resource Exhaustion Prevention**
   - Limits prevent a single container from consuming all resources
   - Protects other workloads from starvation
   - Makes DoS attacks harder

2. **Predictable Performance**
   - Requests help Kubernetes schedule pods appropriately
   - Ensures nodes have enough resources
   - Improves cluster stability

3. **Cost Control**
   - Limits prevent unexpected resource consumption
   - Helps with capacity planning
   - Prevents runaway costs

**Best Practice Example:**
```yaml
containers:
  - name: app
    resources:
      requests:
        memory: "64Mi"   # Minimum resources needed
        cpu: "100m"
      limits:
        memory: "128Mi"  # Maximum resources allowed
        cpu: "200m"
```

**Guidelines:**
- Set requests based on typical usage
- Set limits to prevent resource exhaustion
- Leave headroom: limits should be 1.5-2x requests
- Monitor and adjust based on actual usage

**References:**
- [Kubernetes Resource Management](https://kubernetes.io/docs/concepts/configuration/manage-resources-containers/)
- [CIS Kubernetes Benchmark - Resource Limits](https://www.cisecurity.org/benchmark/kubernetes)

---

## Health Probes

### Recommendation
Always configure `livenessProbe` and `readinessProbe` for application containers.

### Why This Matters

**The Problem:**
Without health probes:
- Kubernetes doesn't know if the application is healthy
- Unhealthy pods continue running and receiving traffic
- Failures go unnoticed
- Degraded performance affects users

**Security and Reliability Benefits:**

1. **Failure Detection**
   - Liveness probe detects when application is dead
   - Kubernetes restarts unhealthy containers automatically
   - Reduces downtime and user impact

2. **Traffic Management**
   - Readiness probe ensures traffic only goes to healthy pods
   - Prevents serving errors to users
   - Improves user experience

3. **Security Monitoring**
   - Health probes can detect certain types of attacks
   - Compromised applications may fail health checks
   - Early detection of issues

**Best Practice Example:**
```yaml
containers:
  - name: app
    livenessProbe:
      httpGet:
        path: /health
        port: 8080
      initialDelaySeconds: 30
      periodSeconds: 10
      timeoutSeconds: 5
      failureThreshold: 3
    readinessProbe:
      httpGet:
        path: /ready
        port: 8080
      initialDelaySeconds: 5
      periodSeconds: 5
      timeoutSeconds: 3
      failureThreshold: 3
```

**References:**
- [Kubernetes Liveness and Readiness Probes](https://kubernetes.io/docs/tasks/configure-pod-container/configure-liveness-readiness-startup-probes/)

---

## Seccomp Profiles

### Recommendation
Set `seccompProfile.type: RuntimeDefault` or use a custom seccomp profile.

### Why This Matters

**The Problem:**
By default, containers can use many Linux system calls (syscalls):
- Some syscalls are dangerous and rarely needed
- Attackers can use syscalls for exploitation
- Unnecessary syscalls increase attack surface

**Security Benefits:**

1. **Syscall Filtering**
   - Seccomp restricts available system calls
   - Reduces available attack surface
   - Prevents use of dangerous syscalls

2. **Runtime Default Profile**
   - `RuntimeDefault` uses the container runtime's default profile
   - Blocks many unnecessary syscalls
   - Good baseline security

3. **Custom Profiles**
   - Can create custom profiles for specific applications
   - Whitelist only required syscalls
   - Maximum security (but requires maintenance)

**Best Practice Example:**
```yaml
securityContext:
  seccompProfile:
    type: RuntimeDefault  # Use runtime's default seccomp profile
```

**References:**
- [Kubernetes Seccomp](https://kubernetes.io/docs/tutorials/security/seccomp/)
- [Seccomp Security Profiles for Docker](https://docs.docker.com/engine/security/seccomp/)

---

## Image Digests

### Recommendation
Use image digests instead of tags: `image: busybox@sha256:abc123...` instead of `image: busybox:1.36`.

### Why This Matters

**The Problem:**
Image tags are mutable:
- `busybox:1.36` can be updated to point to a different image
- Attacker could push malicious image with same tag
- Same tag, different content = security risk
- Hard to track what's actually running

**Security Benefits:**

1. **Immutability**
   - Digests are immutable: same digest = same image
   - Cannot be overwritten or changed
   - Guaranteed image integrity

2. **Supply Chain Security**
   - Know exactly which image is running
   - Reproducible deployments
   - Better security auditing

3. **Prevents Tag Manipulation**
   - Attackers cannot push malicious images with same tag
   - Tags can be overwritten, digests cannot
   - Reduces supply chain attack risk

**Best Practice Example:**
```yaml
containers:
  - name: app
    image: busybox@sha256:1ff6c18fbef2045af6b9c16bf034cc421a29027b800e4f9b68ae9b1cb3e9ae07
    imagePullPolicy: IfNotPresent
```

**Getting Image Digests:**
```bash
# Pull and inspect
docker pull busybox:1.36
docker inspect busybox:1.36 | grep -A 5 RepoDigests

# Or use docker images with digests
docker images --digests busybox:1.36
```

**References:**
- [Kubernetes Image Pull Policy](https://kubernetes.io/docs/concepts/containers/images/#image-pull-policy)
- [OCI Image Specification - Digests](https://github.com/opencontainers/image-spec/blob/main/descriptor.md#digests)

---

## Additional Resources

- [Kubernetes Pod Security Standards](https://kubernetes.io/docs/concepts/security/pod-security-standards/)
- [CIS Kubernetes Benchmark](https://www.cisecurity.org/benchmark/kubernetes)
- [NSA Kubernetes Hardening Guide](https://media.defense.gov/2021/Aug/03/2002820425/-1/-1/0/CTR_KUBERNETES_HARDENING_GUIDANCE_1.1_20220415.PDF)
- [KubeSec Documentation](https://kubesec.io/)
- [Kubernetes Security Best Practices](https://kubernetes.io/docs/concepts/security/)

