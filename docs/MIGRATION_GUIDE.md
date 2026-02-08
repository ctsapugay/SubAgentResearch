# Migration Guide: Directory to Container Isolation

This guide helps you migrate from directory-based sandbox isolation to container-based isolation for enhanced security and resource management.

## Table of Contents

1. [Overview](#overview)
2. [Why Migrate?](#why-migrate)
3. [Prerequisites](#prerequisites)
4. [Migration Steps](#migration-steps)
5. [Code Changes](#code-changes)
6. [Configuration](#configuration)
7. [Testing](#testing)
8. [Rollback](#rollback)
9. [Troubleshooting](#troubleshooting)

---

## Overview

The Skill-to-Sandbox Pipeline supports two isolation modes:

- **Container Mode** (default): Uses Docker containers for OS-level isolation
- **Directory Mode**: Uses directory separation and Python virtual environments

Both modes provide the same API, so migration is straightforward. This guide walks you through the process.

---

## Why Migrate?

Container-based isolation provides:

- **Enhanced Security**: OS-level isolation prevents sandbox escape
- **Resource Limits**: CPU, memory, and process limits enforced by Docker
- **Network Isolation**: Containers can run with no network access
- **Consistency**: Same environment across different host systems
- **Production Ready**: Suitable for running untrusted code

**When to use Directory Mode:**
- Development and testing
- Trusted code execution
- Faster startup requirements
- No Docker available

**When to use Container Mode:**
- Production deployments
- Untrusted code execution
- Resource limit requirements
- Enhanced security needs

---

## Prerequisites

Before migrating, ensure you have:

1. **Docker installed and running**
   ```bash
   # Check Docker installation
   docker --version
   
   # Verify Docker daemon is running
   docker ps
   ```

2. **Docker SDK for Python**
   ```bash
   pip install docker>=6.0.0
   ```

3. **Sufficient resources**
   - Disk space for Docker images (~500MB-2GB per base image)
   - Memory for containers (depends on your limits)
   - CPU cores (containers can share cores)

---

## Migration Steps

### Step 1: Test Container Mode Locally

Start by testing container mode with a simple example:

```python
from src.sandbox_builder import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

# Create a test builder with container mode
config = ContainerConfig(
    resource_limits=ResourceLimits(memory="512m", cpus=1.0)
)

builder = SandboxBuilder(
    isolation_mode="container",
    container_config=config
)

# Test with a simple skill
sandbox_id = builder.build_from_skill_file("examples/simple_skill.md")
print(f"Created container sandbox: {sandbox_id}")

# Test tool execution
result = builder.execute_in_sandbox(
    sandbox_id,
    "write_file",
    file_path="test.txt",
    content="Hello from container!"
)

# Cleanup
builder.cleanup(sandbox_id)
```

### Step 2: Update Your Code

The API is the same, but you need to specify `isolation_mode="container"`:

**Before (Directory Mode):**
```python
from src.sandbox_builder import SandboxBuilder

builder = SandboxBuilder()
sandbox_id = builder.build_from_skill_file("skill.md")
```

**After (Container Mode):**
```python
from src.sandbox_builder import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

config = ContainerConfig(
    resource_limits=ResourceLimits(memory="512m", cpus=1.0)
)

builder = SandboxBuilder(
    isolation_mode="container",
    container_config=config
)
sandbox_id = builder.build_from_skill_file("skill.md")
```

### Step 3: Configure Resource Limits

Set appropriate resource limits for your use case:

```python
from src.sandbox.container_config import ContainerConfig, ResourceLimits

# Conservative limits (good for testing)
config = ContainerConfig(
    resource_limits=ResourceLimits(
        memory="512m",      # 512 MB
        cpus=1.0,           # 1 CPU core
        pids_limit=100      # Max 100 processes
    )
)

# Production limits (adjust based on your needs)
config = ContainerConfig(
    resource_limits=ResourceLimits(
        memory="2g",         # 2 GB
        cpus=2.0,           # 2 CPU cores
        pids_limit=200
    ),
    network_mode="none",    # No network access
    read_only=True          # Read-only root filesystem
)
```

### Step 4: Add Resource Monitoring (Optional)

Monitor container resources:

```python
from src.sandbox.resource_manager import ResourceManager
import docker

docker_client = docker.from_env()
resource_manager = ResourceManager(docker_client, default_config=config)

# Get stats
stats = resource_manager.get_container_stats(sandbox_id)
print(f"CPU: {stats['cpu_percent']}%, Memory: {stats['memory_percent']}%")

# Enforce limits
result = resource_manager.enforce_limits(
    sandbox_id,
    action_on_exceed="warn"  # or "stop", "kill"
)
```

### Step 5: Update Error Handling

Container mode may have different error messages. Update your error handling:

```python
try:
    sandbox_id = builder.build_from_skill_file("skill.md")
except RuntimeError as e:
    if "Docker" in str(e):
        print("Docker is required for container mode")
        # Fallback to directory mode or exit
    raise
```

---

## Code Changes

### Minimal Change (Backward Compatible)

The simplest migration is to add container mode while keeping directory mode as fallback:

```python
from src.sandbox_builder import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

def create_builder(use_container=True):
    """Create builder with optional container mode."""
    if use_container:
        try:
            config = ContainerConfig(
                resource_limits=ResourceLimits(memory="512m", cpus=1.0)
            )
            return SandboxBuilder(
                isolation_mode="container",
                container_config=config
            )
        except RuntimeError:
            # Docker not available, fallback to directory mode
            print("Warning: Docker not available, using directory mode")
            return SandboxBuilder()
    else:
        return SandboxBuilder()

# Usage
builder = create_builder(use_container=True)
```

### Gradual Migration

Migrate sandboxes one at a time:

```python
# Keep directory mode for existing sandboxes
directory_builder = SandboxBuilder(isolation_mode="directory")

# Use container mode for new sandboxes
container_builder = SandboxBuilder(
    isolation_mode="container",
    container_config=config
)

# Migrate existing sandbox
old_sandbox_id = "existing-sandbox-id"
# ... use directory_builder for old sandbox ...

# Create new sandbox with container mode
new_sandbox_id = container_builder.build_from_skill_file("skill.md")
```

---

## Configuration

### Environment Variables

You can use environment variables to configure container mode:

```python
import os
from src.sandbox_builder import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

# Read from environment
use_container = os.getenv("USE_CONTAINER", "false").lower() == "true"
memory_limit = os.getenv("CONTAINER_MEMORY", "512m")
cpu_limit = float(os.getenv("CONTAINER_CPUS", "1.0"))

if use_container:
    config = ContainerConfig(
        resource_limits=ResourceLimits(
            memory=memory_limit,
            cpus=cpu_limit
        )
    )
    builder = SandboxBuilder(isolation_mode="container", container_config=config)
else:
    builder = SandboxBuilder()
```

### Configuration File

Create a configuration file for your project:

```python
# config.py
from src.sandbox.container_config import ContainerConfig, ResourceLimits

CONTAINER_CONFIG = ContainerConfig(
    base_image="python:3.11-slim",
    resource_limits=ResourceLimits(
        memory="1g",
        cpus=2.0,
        pids_limit=150
    ),
    network_mode="none",
    read_only=True
)

# usage.py
from config import CONTAINER_CONFIG
from src.sandbox_builder import SandboxBuilder

builder = SandboxBuilder(
    isolation_mode="container",
    container_config=CONTAINER_CONFIG
)
```

---

## Testing

### Test Checklist

Before deploying to production:

- [ ] Container creation works
- [ ] Tool execution works in containers
- [ ] Resource limits are enforced
- [ ] Cleanup works correctly
- [ ] Error handling works
- [ ] Performance is acceptable
- [ ] Resource monitoring works

### Test Script

```python
import pytest
from src.sandbox_builder import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

def test_container_mode():
    """Test container mode functionality."""
    config = ContainerConfig(
        resource_limits=ResourceLimits(memory="512m", cpus=1.0)
    )
    
    builder = SandboxBuilder(
        isolation_mode="container",
        container_config=config
    )
    
    # Create sandbox
    sandbox_id = builder.build_from_skill_file("examples/simple_skill.md")
    assert sandbox_id is not None
    
    # Execute tool
    result = builder.execute_in_sandbox(
        sandbox_id,
        "write_file",
        file_path="test.txt",
        content="test"
    )
    assert result is not None
    
    # Cleanup
    builder.cleanup(sandbox_id)
```

---

## Rollback

If you need to rollback to directory mode:

1. **Change isolation mode back:**
   ```python
   builder = SandboxBuilder(isolation_mode="directory")
   ```

2. **Clean up containers:**
   ```bash
   docker ps -a | grep sandbox- | awk '{print $1}' | xargs docker rm -f
   docker image prune -a
   ```

3. **Update configuration:**
   Remove container-specific configuration from your code.

---

## Troubleshooting

### Common Issues

**Issue: Docker not running**
```bash
# Start Docker Desktop (macOS/Windows)
# Or start Docker daemon (Linux)
sudo systemctl start docker
```

**Issue: Permission denied**
```bash
# Add user to docker group
sudo usermod -aG docker $USER
# Log out and back in
```

**Issue: Out of disk space**
```bash
# Clean up unused images
docker image prune -a

# Clean up unused containers
docker container prune
```

**Issue: Container creation slow**
- Use smaller base images (`python:3.11-slim` instead of `python:3.11`)
- Enable image caching (already enabled by default)
- Pre-build common images

**Issue: Resource limits too strict**
- Increase memory limit: `ResourceLimits(memory="1g")`
- Increase CPU limit: `ResourceLimits(cpus=2.0)`
- Increase PID limit: `ResourceLimits(pids_limit=200)`

### Getting Help

- Check [docs/DOCKER_IMPLEMENTATION_PLAN.md](DOCKER_IMPLEMENTATION_PLAN.md) for detailed documentation
- Review [docs/SECURITY.md](SECURITY.md) for security considerations
- See [README.md](../README.md) for usage examples

---

## Best Practices

1. **Start Small**: Test with simple skills before migrating complex ones
2. **Monitor Resources**: Use ResourceManager to monitor container usage
3. **Set Appropriate Limits**: Don't set limits too high or too low
4. **Clean Up**: Regularly clean up unused containers and images
5. **Error Handling**: Always handle Docker-related errors gracefully
6. **Fallback**: Consider falling back to directory mode if Docker fails

---

## Next Steps

After successful migration:

1. Monitor container resource usage
2. Adjust resource limits based on actual usage
3. Set up automated cleanup policies
4. Document your container configuration
5. Train your team on container mode usage

Good luck with your migration!
