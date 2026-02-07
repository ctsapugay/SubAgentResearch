# Security Documentation

This document describes security considerations and best practices for the Skill-to-Sandbox Pipeline, with a focus on container-based isolation.

## Table of Contents

1. [Security Overview](#security-overview)
2. [Isolation Modes](#isolation-modes)
3. [Container Security](#container-security)
4. [Resource Limits](#resource-limits)
5. [Network Security](#network-security)
6. [Best Practices](#best-practices)
7. [Security Audit](#security-audit)
8. [Known Limitations](#known-limitations)

---

## Security Overview

The Skill-to-Sandbox Pipeline provides isolation for executing untrusted code. Security is implemented at multiple layers:

1. **Path Isolation**: File operations restricted to sandbox workspace
2. **Process Isolation**: Containers provide OS-level isolation
3. **Resource Limits**: CPU, memory, and process limits
4. **Network Isolation**: Containers can run without network access
5. **Capability Dropping**: Containers run with minimal privileges
6. **Read-Only Filesystem**: Root filesystem can be read-only

---

## Isolation Modes

### Directory Mode

**Security Level**: Medium

**Protection Provided**:
- Path validation prevents access outside sandbox workspace
- Separate Python virtual environments
- Directory-based isolation

**Limitations**:
- No process isolation (runs in host process)
- No resource limits enforced
- Potential for path traversal if validation fails
- System-level dependencies shared

**Use Cases**:
- Development and testing
- Trusted code execution
- Fast iteration cycles

### Container Mode

**Security Level**: High

**Protection Provided**:
- OS-level process isolation
- Resource limits enforced by Docker
- Network isolation
- Read-only root filesystem
- Capability dropping
- Non-root user execution

**Limitations**:
- Requires Docker (additional dependency)
- Higher resource overhead
- Slower startup time

**Use Cases**:
- Production deployments
- Untrusted code execution
- Multi-tenant environments

---

## Container Security

### Default Security Configuration

Containers are configured with security best practices by default:

```python
ContainerConfig(
    # Run as non-root user
    user="sandbox:1000",
    
    # Read-only root filesystem
    read_only=True,
    
    # No network access
    network_mode="none",
    
    # Drop all capabilities
    cap_drop=["ALL"],
    
    # No additional capabilities
    cap_add=[],
    
    # Security options
    security_opt=["no-new-privileges:true"],
    
    # Resource limits
    resource_limits=ResourceLimits(
        memory="512m",
        cpus=1.0,
        pids_limit=100
    )
)
```

### Security Features

#### 1. Non-Root User

Containers run as non-root user (`sandbox:1000`) to prevent privilege escalation:

```python
config = ContainerConfig(user="sandbox:1000")
```

**Benefits**:
- Prevents privilege escalation attacks
- Limits filesystem access
- Reduces attack surface

#### 2. Read-Only Root Filesystem

Root filesystem is mounted read-only, with writable directories via tmpfs:

```python
config = ContainerConfig(
    read_only=True,
    tmpfs=["/tmp", "/workspace/tmp"]
)
```

**Benefits**:
- Prevents modification of system files
- Reduces persistence of malicious code
- Limits attack surface

#### 3. Network Isolation

Containers can run with no network access:

```python
config = ContainerConfig(network_mode="none")
```

**Options**:
- `"none"`: No network access (most secure)
- `"bridge"`: Isolated bridge network
- `"host"`: Use host network (not recommended)

**Benefits**:
- Prevents data exfiltration
- Blocks external communication
- Reduces attack surface

#### 4. Capability Dropping

All Linux capabilities are dropped by default:

```python
config = ContainerConfig(
    cap_drop=["ALL"],
    cap_add=[]  # No additional capabilities
)
```

**Benefits**:
- Prevents privilege escalation
- Limits system call access
- Reduces attack surface

#### 5. Security Options

Additional security hardening:

```python
config = ContainerConfig(
    security_opt=[
        "no-new-privileges:true",  # Prevent privilege escalation
        # "seccomp=unconfined",    # Custom seccomp profile (optional)
        # "apparmor=profile"      # AppArmor profile (optional)
    ]
)
```

---

## Resource Limits

Resource limits prevent resource exhaustion attacks:

### Memory Limits

```python
ResourceLimits(memory="512m")  # 512 MB limit
```

**Protection**:
- Prevents OOM (Out of Memory) attacks
- Limits memory consumption
- Enforced by Docker

### CPU Limits

```python
ResourceLimits(cpus=1.0)  # 1 CPU core
```

**Protection**:
- Prevents CPU exhaustion
- Limits CPU usage
- Uses CFS scheduler

### PID Limits

```python
ResourceLimits(pids_limit=100)  # Max 100 processes
```

**Protection**:
- Prevents fork bombs
- Limits process creation
- Enforced by Docker

### Monitoring and Enforcement

Use `ResourceManager` to monitor and enforce limits:

```python
from src.sandbox.resource_manager import ResourceManager
import docker

docker_client = docker.from_env()
resource_manager = ResourceManager(docker_client, default_config=config)

# Monitor resources
stats = resource_manager.get_container_stats(container_id)

# Enforce limits
result = resource_manager.enforce_limits(
    container_id,
    action_on_exceed="stop"  # Stop container if limits exceeded
)
```

---

## Network Security

### Network Isolation

By default, containers run with `network_mode="none"`:

```python
config = ContainerConfig(network_mode="none")
```

**Benefits**:
- No network access
- Prevents data exfiltration
- Blocks external communication

### If Network Access is Required

If your use case requires network access, use isolated bridge network:

```python
config = ContainerConfig(network_mode="bridge")
```

**Considerations**:
- Containers can communicate with external services
- Data exfiltration is possible
- Use firewall rules if needed
- Monitor network traffic

---

## Best Practices

### 1. Use Container Mode for Untrusted Code

```python
# For untrusted code
builder = SandboxBuilder(isolation_mode="container")

# For trusted code (development)
builder = SandboxBuilder(isolation_mode="directory")
```

### 2. Set Appropriate Resource Limits

```python
# Conservative limits for untrusted code
config = ContainerConfig(
    resource_limits=ResourceLimits(
        memory="256m",      # Small memory limit
        cpus=0.5,          # Half CPU core
        pids_limit=50      # Low process limit
    )
)
```

### 3. Monitor Resource Usage

```python
# Regular monitoring
resource_manager = ResourceManager(docker_client, default_config=config)
stats = resource_manager.get_container_stats(container_id)

if stats['memory_percent'] > 90:
    # Take action
    pass
```

### 4. Enforce Limits Automatically

```python
# Automatic enforcement
result = resource_manager.enforce_limits(
    container_id,
    action_on_exceed="stop"  # Stop on violation
)

# Cleanup exceeded containers
cleaned = resource_manager.cleanup_exceeded_containers(
    exceeded_duration=300,  # 5 minutes
    max_exceeded_count=10,
    action="stop"
)
```

### 5. Use Read-Only Filesystem

```python
config = ContainerConfig(read_only=True)
```

### 6. Run as Non-Root User

```python
config = ContainerConfig(user="sandbox:1000")
```

### 7. Drop All Capabilities

```python
config = ContainerConfig(
    cap_drop=["ALL"],
    cap_add=[]  # Only add if absolutely necessary
)
```

### 8. Regular Cleanup

```python
# Clean up unused containers
builder.cleanup_all()

# Clean up Docker images
docker_client.images.prune()
```

---

## Security Audit

### Checklist

- [ ] Containers run as non-root user
- [ ] Root filesystem is read-only
- [ ] Network access is disabled (or isolated)
- [ ] All capabilities are dropped
- [ ] Resource limits are set
- [ ] Resource monitoring is enabled
- [ ] Limits are enforced automatically
- [ ] Cleanup policies are in place
- [ ] Base images are from trusted sources
- [ ] Base images are regularly updated
- [ ] Security options are configured
- [ ] Logging is enabled for security events

### Security Testing

Test security configuration:

```python
# Test path traversal prevention
try:
    builder.execute_in_sandbox(
        sandbox_id,
        "read_file",
        file_path="../../etc/passwd"  # Should fail
    )
except ValueError:
    print("✓ Path traversal prevented")

# Test resource limits
# Run resource-intensive operation
# Verify container is stopped/killed when limit exceeded

# Test network isolation
# Try to connect to external service
# Should fail if network_mode="none"
```

---

## Known Limitations

### 1. Docker Dependency

Container mode requires Docker, which adds:
- Additional installation complexity
- Resource overhead
- Potential security vulnerabilities in Docker itself

**Mitigation**: Keep Docker updated, use directory mode when appropriate

### 2. Container Escape

While rare, container escape vulnerabilities exist in Docker.

**Mitigation**: 
- Keep Docker updated
- Use security options
- Monitor for security advisories
- Use additional security layers (seccomp, AppArmor)

### 3. Resource Limits Not Perfect

Resource limits can be bypassed in some edge cases.

**Mitigation**:
- Use conservative limits
- Monitor resource usage
- Enforce limits automatically

### 4. Path Validation

Path validation relies on correct implementation.

**Mitigation**:
- Defense in depth (path validation + container isolation)
- Regular security audits
- Comprehensive testing

### 5. Base Image Security

Base images may contain vulnerabilities.

**Mitigation**:
- Use official, minimal base images
- Regularly update base images
- Scan images for vulnerabilities
- Use `python:3.11-slim` (minimal image)

---

## Reporting Security Issues

If you discover a security vulnerability, please:

1. **Do not** open a public issue
2. Email security concerns to: [security contact]
3. Include:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

---

## References

- [Docker Security Best Practices](https://docs.docker.com/engine/security/)
- [OWASP Container Security](https://owasp.org/www-project-container-security/)
- [CIS Docker Benchmark](https://www.cisecurity.org/benchmark/docker)

---

## Conclusion

The Skill-to-Sandbox Pipeline provides multiple layers of security:

1. **Path Isolation**: Basic protection in directory mode
2. **Container Isolation**: Strong protection in container mode
3. **Resource Limits**: Prevents resource exhaustion
4. **Network Isolation**: Prevents data exfiltration
5. **Capability Dropping**: Reduces attack surface

For production use with untrusted code, **always use container mode** with appropriate security configuration.

For development and trusted code, directory mode provides sufficient isolation with better performance.
