# Docker Container Implementation Plan

**Project**: Skill-to-Sandbox Pipeline  
**Feature**: Docker Container Support for Enhanced Isolation  
**Date**: February 2026  
**Status**: Implementation Phase - Phase 6 Complete ✅

## Table of Contents

1. [Executive Summary](#executive-summary)
2. [Current Architecture Analysis](#current-architecture-analysis)
3. [Docker Integration Design](#docker-integration-design)
4. [Implementation Phases](#implementation-phases)
5. [Detailed Implementation Steps](#detailed-implementation-steps)
6. [Security Considerations](#security-considerations)
7. [Resource Management](#resource-management)
8. [Testing Strategy](#testing-strategy)
9. [Migration Path](#migration-path)
10. [Performance Considerations](#performance-considerations)
11. [Troubleshooting Guide](#troubleshooting-guide)

---

## Executive Summary

This document provides a comprehensive implementation plan for adding Docker container support to the Skill-to-Sandbox Pipeline project. Docker containers will provide stronger isolation, security, and resource management compared to the current directory-based sandbox approach.

### Key Benefits

- **Enhanced Security**: OS-level isolation prevents sandbox escape
- **Resource Limits**: CPU, memory, and network limits per sandbox
- **Consistency**: Same environment across different host systems
- **Dependency Isolation**: System-level dependencies isolated per sandbox
- **Production Ready**: Suitable for running untrusted code

### Current State

The project currently uses:
- Directory-based isolation (`sandboxes/{sandbox_id}/`)
- Python virtual environments for package isolation
- Path validation for security
- No resource limits or process isolation

### Target State

After implementation:
- Docker containers for each sandbox
- Container-based tool execution
- Resource limits and monitoring
- Backward compatibility with directory-based sandboxes
- Configurable isolation level (directory vs container)

---

## Current Architecture Analysis

### Existing Components

#### 1. EnvironmentBuilder (`src/sandbox/environment.py`)
- **Current Role**: Creates directory structures and Python virtual environments
- **Key Methods**:
  - `create_environment()`: Creates sandbox directory, venv, installs packages
  - `cleanup()`: Removes sandbox directory
- **Dependencies**: Uses `subprocess` for venv creation and pip installation

#### 2. SandboxManager (`src/sandbox/manager.py`)
- **Current Role**: Manages sandbox lifecycle and tool execution
- **Key Methods**:
  - `create_sandbox()`: Creates sandbox from skill definition
  - `execute_tool()`: Executes tools within sandbox workspace
  - `cleanup_sandbox()`: Cleans up sandbox
- **Dependencies**: EnvironmentBuilder, ToolRegistry

#### 3. Tool System (`src/tools/`)
- **Current Role**: Provides tool implementations (filesystem tools)
- **Key Classes**: `ReadFileTool`, `WriteFileTool`, `ListFilesTool`
- **Execution Model**: Tools execute directly in host process with path restrictions

#### 4. SandboxBuilder (`src/sandbox_builder.py`)
- **Current Role**: Main public interface
- **Key Methods**: `build_from_skill_file()`, `execute_in_sandbox()`, `cleanup()`

### Current Isolation Mechanism

1. **Path Isolation**: Tools validate paths are within `sandbox/workspace/`
2. **Directory Separation**: Each sandbox has unique directory
3. **Virtual Environment**: Separate Python environment per sandbox
4. **No Process Isolation**: Tools run in same process as host
5. **No Resource Limits**: No CPU/memory restrictions

### Limitations of Current Approach

1. **Security**: Path validation can be bypassed with symlinks or race conditions
2. **Process Isolation**: Malicious code could affect host system
3. **Resource Usage**: No limits on CPU, memory, or disk usage
4. **System Dependencies**: Cannot isolate system-level packages
5. **Network Access**: No network isolation or restrictions

---

## Docker Integration Design

### Architecture Overview

```
┌─────────────────────────────────────────────────────────────┐
│                    SandboxBuilder                           │
│                  (Public Interface)                          │
└───────────────────────┬─────────────────────────────────────┘
                        │
                        ▼
┌─────────────────────────────────────────────────────────────┐
│                  SandboxManager                             │
│         (Lifecycle Management)                               │
└───────────┬───────────────────────────────┬─────────────────┘
            │                               │
            ▼                               ▼
┌──────────────────────┐      ┌──────────────────────────────┐
│ EnvironmentBuilder   │      │   ContainerManager            │
│  (Directory-based)   │      │   (Docker-based)              │
└──────────────────────┘      └───────────┬──────────────────┘
                                          │
                                          ▼
                          ┌──────────────────────────────┐
                          │   Docker Engine              │
                          │   - Container Creation      │
                          │   - Tool Execution           │
                          │   - Resource Management      │
                          └──────────────────────────────┘
```

### Design Principles

1. **Backward Compatibility**: Existing directory-based sandboxes continue to work
2. **Configurable**: Choose isolation level (directory vs container) per sandbox
3. **Transparent**: Same API for both isolation methods
4. **Extensible**: Easy to add new container backends (Podman, etc.)

### New Components

#### 1. ContainerManager (`src/sandbox/container.py`)
- **Purpose**: Manages Docker container lifecycle
- **Responsibilities**:
  - Create Docker containers from skill definitions
  - Execute tools within containers
  - Manage container resources and limits
  - Clean up containers

#### 2. ContainerEnvironmentBuilder (`src/sandbox/container_environment.py`)
- **Purpose**: Builds Docker images and containers
- **Responsibilities**:
  - Generate Dockerfiles from skill requirements
  - Build Docker images
  - Create and configure containers
  - Install packages within containers

#### 3. ContainerToolExecutor (`src/sandbox/container_executor.py`)
- **Purpose**: Executes tools within Docker containers
- **Responsibilities**:
  - Serialize tool calls
  - Execute commands in containers
  - Retrieve results
  - Handle errors and timeouts

#### 4. DockerImageBuilder (`src/sandbox/docker_image_builder.py`)
- **Purpose**: Builds optimized Docker images
- **Responsibilities**:
  - Generate Dockerfiles dynamically
  - Build images with caching
  - Tag and manage images
  - Clean up unused images

### Configuration

#### SandboxBuilder Configuration

```python
builder = SandboxBuilder(
    sandbox_base_path="./sandboxes",
    isolation_mode="container",  # "directory" | "container" | "auto"
    container_config={
        "image_base": "python:3.11-slim",
        "resource_limits": {
            "memory": "512m",
            "cpus": "1.0",
            "pids_limit": 100
        },
        "network_mode": "none",  # "none" | "bridge" | "host"
        "read_only": True,
        "tmpfs": ["/tmp", "/workspace/tmp"]
    }
)
```

#### Skill-Level Configuration

Skills can specify container requirements in their definition:

```markdown
## Container Requirements
- base_image: python:3.11-slim
- memory_limit: 1GB
- cpu_limit: 2.0
- network_access: false
- system_packages:
  - git
  - curl
```

---

## Implementation Phases

### Phase 1: Foundation (Week 1-2)
- Set up Docker SDK integration
- Create ContainerManager skeleton
- Implement basic container creation/cleanup
- Add Docker dependency and configuration

### Phase 2: Environment Building (Week 2-3)
- Implement DockerImageBuilder
- Create dynamic Dockerfile generation
- Implement package installation in containers
- Add image caching and management

### Phase 3: Tool Execution (Week 3-4) ✅ **COMPLETE**
- ✅ Implement ContainerToolExecutor
- ✅ Adapt filesystem tools for container execution (tools work via script execution)
- ✅ Add result serialization/deserialization
- ✅ Implement timeout and error handling

### Phase 4: Integration (Week 4-5) ✅ **COMPLETE**
- ✅ Integrate ContainerManager into SandboxManager
- ✅ Add isolation mode selection
- ✅ Update SandboxBuilder API
- ✅ Maintain backward compatibility
- ✅ Update all tests
- ✅ Write integration tests

### Phase 5: Resource Management (Week 5-6) ✅ **COMPLETE**
- ✅ Implement resource limits
- ✅ Add resource monitoring
- ✅ Implement cleanup policies
- ✅ Add resource usage reporting

### Phase 6: Testing & Documentation (Week 6-7) ✅ **COMPLETE**
- ✅ Write comprehensive tests
- ✅ Update documentation
- ✅ Create migration guide
- ✅ Performance benchmarking

---

## Detailed Implementation Steps

### Step 1: Add Docker Dependency

**File**: `requirements.txt`

```python
# Container support
docker>=6.0.0  # Docker SDK for Python
```

**Action Items**:
1. ✅ Uncomment docker dependency in `requirements.txt`
2. ✅ Add version constraint: `docker>=6.0.0`
3. ✅ Update installation instructions in README

**Testing**:
```bash
pip install docker>=6.0.0
python -c "import docker; print(docker.__version__)"
```

**Status**: ✅ **COMPLETED**
- Docker dependency uncommented in `requirements.txt` with version `>=6.0.0`
- README.md updated with Docker prerequisites and installation instructions
- Docker SDK verified: Version 7.1.0 installed and working
- Installation instructions include verification steps

---

### Step 2: Create Container Configuration Classes

**File**: `src/sandbox/container_config.py`

**Purpose**: Define configuration data structures for containers

**Implementation**:

```python
"""Configuration classes for Docker container management."""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Union


@dataclass
class ResourceLimits:
    """Resource limits for containers."""
    memory: Optional[str] = None  # e.g., "512m", "1g"
    cpus: Optional[Union[float, str]] = None  # e.g., 1.0, "1.5"
    pids_limit: Optional[int] = None
    ulimits: Optional[List[Dict[str, int]]] = None


@dataclass
class ContainerConfig:
    """Configuration for Docker containers."""
    base_image: str = "python:3.11-slim"
    resource_limits: ResourceLimits = field(default_factory=ResourceLimits)
    network_mode: str = "none"  # "none" | "bridge" | "host"
    read_only: bool = True
    tmpfs: List[str] = field(default_factory=lambda: ["/tmp", "/workspace/tmp"])
    environment_vars: Dict[str, str] = field(default_factory=dict)
    volumes: Dict[str, Dict[str, str]] = field(default_factory=dict)
    working_dir: str = "/workspace"
    user: Optional[str] = None  # Run as non-root user
    cap_drop: List[str] = field(default_factory=lambda: ["ALL"])
    cap_add: List[str] = field(default_factory=list)
    security_opt: List[str] = field(default_factory=lambda: ["no-new-privileges:true"])
```

**Action Items**:
1. ✅ Create `src/sandbox/container_config.py`
2. ✅ Implement `ResourceLimits` and `ContainerConfig` dataclasses
3. ✅ Add validation methods
4. ✅ Write unit tests

**Testing**:
```python
from src.sandbox.container_config import ContainerConfig, ResourceLimits

config = ContainerConfig(
    base_image="python:3.11-slim",
    resource_limits=ResourceLimits(memory="512m", cpus=1.0)
)
assert config.base_image == "python:3.11-slim"
```

**Status**: ✅ **COMPLETED**
- Created `src/sandbox/container_config.py` with `ResourceLimits` and `ContainerConfig` dataclasses
- Implemented comprehensive validation methods:
  - Memory format validation (supports "512m", "1g", "2GB", etc.)
  - CPU limit validation (supports float and string formats)
  - PID limit validation
  - Ulimits validation
  - Network mode validation
  - Working directory validation (must be absolute path)
  - Tmpfs path validation
  - Capability validation
- Added `to_docker_dict()` method to convert config to Docker API format
- Created comprehensive unit tests in `tests/test_container_config.py` (34 tests, all passing)
- Updated `src/sandbox/__init__.py` to export `ContainerConfig` and `ResourceLimits`
- All validation includes proper error messages
- Full type hints throughout

---

### Step 3: Implement DockerImageBuilder

**File**: `src/sandbox/docker_image_builder.py`

**Purpose**: Build Docker images from skill requirements

**Key Methods**:

```python
class DockerImageBuilder:
    def __init__(self, docker_client: docker.DockerClient):
        """Initialize with Docker client."""
        
    def build_image_from_skill(
        self, 
        skill: SkillDefinition, 
        base_image: str = "python:3.11-slim"
    ) -> str:
        """Build Docker image for a skill.
        
        Returns:
            Image tag/ID
        """
        
    def _generate_dockerfile(
        self, 
        skill: SkillDefinition, 
        base_image: str
    ) -> str:
        """Generate Dockerfile content."""
        
    def _install_packages_in_image(
        self, 
        dockerfile: str, 
        packages: List[str]
    ) -> str:
        """Add package installation to Dockerfile."""
        
    def cleanup_unused_images(self, older_than_days: int = 7):
        """Remove unused images."""
```

**Dockerfile Generation Logic**:

```dockerfile
FROM {base_image}

# Set working directory
WORKDIR /workspace

# Create non-root user
RUN useradd -m -u 1000 sandbox && \
    chown -R sandbox:sandbox /workspace

# Install system packages if needed
RUN apt-get update && \
    apt-get install -y {system_packages} && \
    rm -rf /var/lib/apt/lists/*

# Install Python packages
RUN pip install --no-cache-dir {packages}

# Switch to non-root user
USER sandbox

# Set environment variables
ENV PYTHONUNBUFFERED=1
ENV PYTHONPATH=/workspace
```

**Action Items**:
1. ✅ Create `src/sandbox/docker_image_builder.py`
2. ✅ Implement Dockerfile generation
3. ✅ Implement image building with caching
4. ✅ Add image tagging strategy (use skill hash)
5. ✅ Implement cleanup methods
6. ✅ Write unit tests with Docker mock

**Status**: ✅ **COMPLETED**
- Created `src/sandbox/docker_image_builder.py` with full `DockerImageBuilder` implementation
- Implemented `_generate_dockerfile()` to create Dockerfiles from skill requirements
  - Supports Python packages, system packages, and base image configuration
  - Creates non-root user for security
  - Sets up proper working directory and environment variables
- Implemented `build_image_from_skill()` with image caching
  - Checks if image exists before building
  - Generates deterministic tags from skill hash for efficient caching
  - Supports custom tags and build arguments
- Implemented `_generate_image_tag()` using SHA256 hash of requirements
  - Consistent tagging for same skill requirements
  - Different tags for different requirements
- Implemented cleanup methods:
  - `cleanup_unused_images()` removes old images based on age
  - `get_image_info()` retrieves image metadata
  - `list_images()` lists images with prefix filtering
- Comprehensive unit tests created in `tests/test_docker_image_builder.py` (29 tests, all passing)
- Updated `src/sandbox/__init__.py` to export `DockerImageBuilder`
- Full type hints and logging throughout
- Proper error handling for Docker operations

**Testing**:
```python
from src.sandbox.docker_image_builder import DockerImageBuilder
import docker

client = docker.from_env()
builder = DockerImageBuilder(client)

# Test Dockerfile generation
dockerfile = builder._generate_dockerfile(skill, "python:3.11-slim")
assert "FROM python:3.11-slim" in dockerfile
```

---

### Step 4: Implement ContainerManager

**File**: `src/sandbox/container.py`

**Purpose**: Manage Docker container lifecycle

**Key Methods**:

```python
class ContainerManager:
    def __init__(
        self, 
        docker_client: docker.DockerClient,
        base_path: str = "./sandboxes"
    ):
        """Initialize container manager."""
        
    def create_container(
        self,
        skill: SkillDefinition,
        sandbox_id: str,
        image_tag: str,
        config: ContainerConfig
    ) -> str:
        """Create a Docker container for a sandbox.
        
        Returns:
            Container ID
        """
        
    def start_container(self, container_id: str) -> None:
        """Start a container."""
        
    def stop_container(self, container_id: str) -> None:
        """Stop a container."""
        
    def remove_container(self, container_id: str) -> None:
        """Remove a container."""
        
    def execute_in_container(
        self,
        container_id: str,
        command: List[str],
        timeout: int = 30
    ) -> Dict[str, Any]:
        """Execute a command in container.
        
        Returns:
            {
                "exit_code": int,
                "stdout": str,
                "stderr": str,
                "error": Optional[str]
            }
        """
        
    def get_container_info(self, container_id: str) -> Dict[str, Any]:
        """Get container information."""
        
    def list_containers(self, sandbox_id: Optional[str] = None) -> List[str]:
        """List containers, optionally filtered by sandbox_id."""
        
    def cleanup_containers(self, sandbox_id: Optional[str] = None) -> int:
        """Clean up containers."""
```

**Container Creation Logic**:

```python
def create_container(self, skill, sandbox_id, image_tag, config):
    # Create volume mapping
    workspace_path = Path(self.base_path) / sandbox_id / "workspace"
    workspace_path.mkdir(parents=True, exist_ok=True)
    
    volumes = {
        str(workspace_path): {
            "bind": "/workspace",
            "mode": "rw"
        }
    }
    
    # Create container
    container = self.docker_client.containers.create(
        image=image_tag,
        name=f"sandbox-{sandbox_id}",
        working_dir=config.working_dir,
        volumes=volumes,
        network_mode=config.network_mode,
        mem_limit=config.resource_limits.memory,
        cpu_quota=int(config.resource_limits.cpus * 100000) if config.resource_limits.cpus else None,
        cpu_period=100000,
        pids_limit=config.resource_limits.pids_limit,
        read_only=config.read_only,
        tmpfs=config.tmpfs,
        environment=config.environment_vars,
        user=config.user,
        cap_drop=config.cap_drop,
        cap_add=config.cap_add,
        security_opt=config.security_opt,
        detach=True,
        auto_remove=False  # We'll manage cleanup
    )
    
    return container.id
```

**Action Items**:
1. ✅ Create `src/sandbox/container.py`
2. ✅ Implement container creation with all security options
3. ✅ Implement execution methods
4. ✅ Add container state management
5. ✅ Implement cleanup logic
6. ✅ Write unit tests with Docker mock

**Status**: ✅ **COMPLETED**
- Created `src/sandbox/container.py` with full `ContainerManager` implementation
- Implemented all required methods: `create_container()`, `start_container()`, `stop_container()`, `remove_container()`, `execute_in_container()`, `get_container_info()`, `list_containers()`, `cleanup_containers()`
- Container creation includes all security options: resource limits, read-only filesystem, tmpfs mounts, capability dropping, network isolation
- Proper error handling for all Docker operations (NotFound, APIError)
- Comprehensive unit tests created in `tests/test_container.py` (27 tests, all passing)
- Matches `ContainerManagerProtocol` interface expected by `ContainerToolExecutor`
- Full type hints and logging throughout
- Updated `src/sandbox/__init__.py` to export `ContainerManager`

**Testing**:
```python
from src.sandbox.container import ContainerManager
import docker

client = docker.from_env()
manager = ContainerManager(client)

# Test container creation
container_id = manager.create_container(skill, "test-id", "image:tag", config)
assert container_id is not None
```

---

### Step 5: Implement ContainerToolExecutor

**File**: `src/sandbox/container_executor.py`

**Purpose**: Execute tools within Docker containers

**Key Methods**:

```python
class ContainerToolExecutor:
    def __init__(self, container_manager: ContainerManager):
        """Initialize executor with container manager."""
        
    def execute_tool(
        self,
        container_id: str,
        tool_name: str,
        tool_args: Dict[str, Any]
    ) -> Any:
        """Execute a tool within a container.
        
        Args:
            container_id: Container to execute in
            tool_name: Name of tool to execute
            tool_args: Arguments for the tool
            
        Returns:
            Tool execution result
        """
        
    def _create_tool_script(
        self,
        tool_name: str,
        tool_args: Dict[str, Any]
    ) -> str:
        """Create Python script to execute tool."""
        
    def _execute_script_in_container(
        self,
        container_id: str,
        script: str
    ) -> Dict[str, Any]:
        """Execute Python script in container."""
```

**Tool Execution Strategy**:

1. **Serialization**: Convert tool call to JSON
2. **Script Generation**: Create Python script that:
   - Imports tool class
   - Instantiates tool with workspace path
   - Executes tool with arguments
   - Serializes result to JSON
3. **Execution**: Run script in container via `docker exec`
4. **Deserialization**: Parse JSON result

**Example Script Generation**:

```python
def _create_tool_script(self, tool_name, tool_args):
    script = f"""
import json
import sys
from pathlib import Path

# Import tool
from src.tools.implementations.filesystem import {self._get_tool_class(tool_name)}

# Create tool instance
tool = {self._get_tool_class(tool_name)}(base_path="/workspace")

# Execute tool
try:
    result = tool.execute(**{repr(tool_args)})
    # Serialize result
    if isinstance(result, (dict, list, str, int, float, bool, type(None))):
        output = json.dumps({{"success": True, "result": result}})
    else:
        output = json.dumps({{"success": True, "result": str(result)}})
except Exception as e:
    output = json.dumps({{"success": False, "error": str(e)}})

print(output)
sys.stdout.flush()
"""
    return script
```

**Action Items**:
1. ✅ Create `src/sandbox/container_executor.py`
2. ✅ Implement tool script generation
3. ✅ Implement script execution in containers
4. ✅ Add result serialization/deserialization
5. ✅ Handle errors and timeouts
6. ✅ Write unit tests

**Testing**:
```python
from src.sandbox.container_executor import ContainerToolExecutor

executor = ContainerToolExecutor(container_manager)
result = executor.execute_tool(
    container_id="test-container",
    tool_name="read_file",
    tool_args={"file_path": "test.txt"}
)
assert result is not None
```

**Status**: ✅ **COMPLETED**
- Created `src/sandbox/container_executor.py` with `ContainerToolExecutor` class
- Implemented tool script generation that:
  - Dynamically imports tool classes based on tool name
  - Properly serializes tool arguments using JSON
  - Handles special characters and complex data types
  - Includes comprehensive error handling with traceback capture
- Implemented script execution via container manager protocol
- Added result serialization/deserialization with JSON
- Implemented timeout handling (configurable per call or default)
- Comprehensive error handling:
  - Container execution errors
  - Non-zero exit codes
  - JSON parsing errors
  - Tool execution failures with full traceback
- Created comprehensive unit tests in `tests/test_container_executor.py` (24 tests, all passing)
- Uses Protocol for ContainerManager interface (enables testing without full implementation)
- Supports all filesystem tools: read_file, write_file, list_files
- Updated `src/sandbox/__init__.py` to export `ContainerToolExecutor`

---

### Step 6: Create ContainerEnvironmentBuilder

**File**: `src/sandbox/container_environment.py`

**Purpose**: Build container environments (replaces/supplements EnvironmentBuilder)

**Key Methods**:

```python
class ContainerEnvironmentBuilder:
    def __init__(
        self,
        docker_client: docker.DockerClient,
        base_path: str = "./sandboxes"
    ):
        """Initialize container environment builder."""
        self.docker_client = docker_client
        self.image_builder = DockerImageBuilder(docker_client)
        self.container_manager = ContainerManager(docker_client, base_path)
        self.base_path = Path(base_path)
        
    def create_environment(
        self,
        skill: SkillDefinition,
        sandbox_id: str,
        config: Optional[ContainerConfig] = None
    ) -> Dict[str, Any]:
        """Create a container environment for a skill.
        
        Returns:
            {
                "sandbox_id": str,
                "container_id": str,
                "image_tag": str,
                "workspace_path": str
            }
        """
        # Generate image tag from skill
        image_tag = self._generate_image_tag(skill, sandbox_id)
        
        # Build Docker image
        if not self._image_exists(image_tag):
            self.image_builder.build_image_from_skill(skill, config.base_image)
        
        # Create container
        container_id = self.container_manager.create_container(
            skill, sandbox_id, image_tag, config
        )
        
        # Start container
        self.container_manager.start_container(container_id)
        
        # Create workspace directory structure
        workspace_path = self.base_path / sandbox_id / "workspace"
        workspace_path.mkdir(parents=True, exist_ok=True)
        
        # Save metadata
        self._save_metadata(sandbox_path, skill, container_id, image_tag)
        
        return {
            "sandbox_id": sandbox_id,
            "container_id": container_id,
            "image_tag": image_tag,
            "workspace_path": str(workspace_path)
        }
        
    def cleanup(self, sandbox_id: str) -> bool:
        """Clean up container environment."""
        # Stop and remove container
        # Remove image if not used by other sandboxes
        # Remove workspace directory
        pass
```

**Action Items**:
1. ✅ Create `src/sandbox/container_environment.py`
2. ✅ Integrate DockerImageBuilder and ContainerManager
3. ✅ Implement environment creation
4. ✅ Implement cleanup
5. ✅ Add metadata saving
6. ✅ Write unit tests

**Status**: ✅ **COMPLETED**
- Created `src/sandbox/container_environment.py` with full `ContainerEnvironmentBuilder` implementation
- Integrates `DockerImageBuilder` and `ContainerManager` to orchestrate container environment creation
- Implemented `create_environment()` method that:
  - Generates image tag from skill requirements
  - Builds Docker image if it doesn't exist (with caching)
  - Creates and starts Docker container
  - Sets up workspace and logs directories
  - Saves comprehensive metadata (skill info, container info, config)
- Implemented `cleanup()` method that:
  - Stops and removes container
  - Optionally removes Docker image
  - Removes workspace directory
  - Handles errors gracefully
- Comprehensive metadata saving includes:
  - Skill information (name, description, tools, requirements)
  - Container information (container_id, image_tag)
  - Container configuration
  - Workspace and logs paths
- Comprehensive unit tests created in `tests/test_container_environment.py` (16 tests, all passing)
- Updated `src/sandbox/__init__.py` to export `ContainerEnvironmentBuilder`
- Full type hints and logging throughout
- Proper error handling with cleanup on failure

---

### Step 7: Integrate into SandboxManager

**File**: `src/sandbox/manager.py`

**Changes Needed**:

1. **Add Isolation Mode**:
```python
class SandboxManager:
    def __init__(
        self, 
        base_path: str = "./sandboxes",
        isolation_mode: str = "directory"  # "directory" | "container"
    ):
        self.isolation_mode = isolation_mode
        self.environment_builder = EnvironmentBuilder(str(self.base_path))
        
        if isolation_mode == "container":
            import docker
            docker_client = docker.from_env()
            self.container_environment_builder = ContainerEnvironmentBuilder(
                docker_client, str(self.base_path)
            )
            self.container_manager = ContainerManager(docker_client, str(self.base_path))
            self.container_executor = ContainerToolExecutor(self.container_manager)
```

2. **Update create_sandbox()**:
```python
def create_sandbox(
    self, 
    skill: SkillDefinition,
    container_config: Optional[ContainerConfig] = None
) -> str:
    sandbox_id = str(uuid.uuid4())
    
    if self.isolation_mode == "container":
        # Use container-based environment
        env_info = self.container_environment_builder.create_environment(
            skill, sandbox_id, container_config
        )
        container_id = env_info["container_id"]
        workspace_path = Path(env_info["workspace_path"])
    else:
        # Use directory-based environment (existing code)
        sandbox_path = self.environment_builder.create_environment(skill, sandbox_id)
        workspace_path = sandbox_path / "workspace"
        container_id = None
    
    # Initialize tools
    tools = {}
    for tool_name in skill.get_tool_names():
        if self.isolation_mode == "container":
            # Tools will be executed via container executor
            tools[tool_name] = None  # Placeholder, actual execution via executor
        else:
            tool_instance = self.tool_registry.get_tool(
                tool_name, base_path=str(workspace_path)
            )
            if tool_instance:
                tools[tool_name] = tool_instance
    
    # Store sandbox info
    sandbox_info = {
        "sandbox_id": sandbox_id,
        "skill": skill,
        "workspace_path": workspace_path,
        "tools": tools,
        "status": "active",
        "isolation_mode": self.isolation_mode,
        "container_id": container_id
    }
    
    self.active_sandboxes[sandbox_id] = sandbox_info
    return sandbox_id
```

3. **Update execute_tool()**:
```python
def execute_tool(
    self,
    sandbox_id: str,
    tool_name: str,
    **kwargs
) -> Any:
    if sandbox_id not in self.active_sandboxes:
        raise ValueError(f"Sandbox {sandbox_id} not found")
    
    sandbox_info = self.active_sandboxes[sandbox_id]
    
    if sandbox_info["isolation_mode"] == "container":
        # Execute via container executor
        container_id = sandbox_info["container_id"]
        return self.container_executor.execute_tool(
            container_id, tool_name, kwargs
        )
    else:
        # Execute directly (existing code)
        if tool_name not in sandbox_info["tools"]:
            raise ValueError(f"Tool '{tool_name}' not available")
        tool = sandbox_info["tools"][tool_name]
        return tool.execute(**kwargs)
```

4. **Update cleanup_sandbox()**:
```python
def cleanup_sandbox(self, sandbox_id: str) -> bool:
    if sandbox_id not in self.active_sandboxes:
        return False
    
    sandbox_info = self.active_sandboxes.pop(sandbox_id)
    
    if sandbox_info["isolation_mode"] == "container":
        # Clean up container
        self.container_environment_builder.cleanup(sandbox_id)
    else:
        # Clean up directory (existing code)
        self.environment_builder.cleanup(sandbox_id)
    
    return True
```

**Action Items**:
1. ✅ Update `SandboxManager.__init__()` to accept isolation_mode
2. ✅ Update `create_sandbox()` to support both modes
3. ✅ Update `execute_tool()` to route to container executor
4. ✅ Update `cleanup_sandbox()` to handle containers
5. ✅ Update unit tests
6. ✅ Ensure backward compatibility

**Status**: ✅ **COMPLETED**
- Updated `SandboxManager` to support both directory and container isolation modes
- Added `isolation_mode` and `container_config` parameters to `__init__()`
- Conditionally initializes container components when `isolation_mode="container"`
- Updated `create_sandbox()` to create environments based on isolation mode
- Updated `execute_tool()` to route to container executor for container mode
- Updated `cleanup_sandbox()` to handle both directory and container cleanup
- Updated `get_sandbox()` to include isolation mode info and container_id
- Comprehensive error handling for Docker availability
- Full backward compatibility maintained (defaults to "directory" mode)
- Updated unit tests in `tests/test_sandbox_manager.py` to test new parameters

---

### Step 8: Update SandboxBuilder API

**File**: `src/sandbox_builder.py`

**Changes Needed**:

```python
class SandboxBuilder:
    def __init__(
        self, 
        sandbox_base_path: str = "./sandboxes",
        isolation_mode: str = "directory",  # "directory" | "container" | "auto"
        container_config: Optional[ContainerConfig] = None
    ):
        """Initialize the sandbox builder.
        
        Args:
            sandbox_base_path: Base directory for sandboxes
            isolation_mode: Isolation method ("directory", "container", or "auto")
            container_config: Configuration for container mode
        """
        self.isolation_mode = isolation_mode
        self.container_config = container_config or ContainerConfig()
        
        self.skill_parser = SkillParser()
        self.sandbox_manager = SandboxManager(
            sandbox_base_path,
            isolation_mode=isolation_mode
        )
```

**Action Items**:
1. ✅ Update `SandboxBuilder.__init__()` signature
2. ✅ Pass isolation_mode to SandboxManager
3. ✅ Update documentation
4. ✅ Add examples for container mode
5. ✅ Update tests

**Status**: ✅ **COMPLETED**
- Updated `SandboxBuilder.__init__()` to accept `isolation_mode` and `container_config` parameters
- Updated `build_from_skill_file()` and `build_from_skill_definition()` to accept optional `container_config`
- Updated documentation strings to reflect container mode support
- Maintains full backward compatibility (defaults to "directory" mode)
- Updated unit tests in `tests/test_sandbox_builder.py` to verify isolation mode support
- Added integration tests in `tests/integration_test.py` for container mode:
  - Container sandbox creation and tool execution
  - Container isolation verification
  - Custom container configuration
  - Backward compatibility verification

---

## Phase 4 Completion Summary

**Status**: ✅ **PHASE 4 COMPLETE**

### Completed Components

1. **SandboxManager Integration** (`src/sandbox/manager.py`)
   - Added `isolation_mode` parameter ("directory" | "container") to `__init__()`
   - Added optional `container_config` parameter
   - Conditionally initializes container components when `isolation_mode="container"`
   - Updated `create_sandbox()` to support both directory and container modes
   - Updated `execute_tool()` to route to container executor for container mode
   - Updated `cleanup_sandbox()` to handle both directory and container cleanup
   - Updated `get_sandbox()` to include isolation mode info and container_id
   - Comprehensive error handling for Docker availability
   - Full backward compatibility maintained (defaults to "directory" mode)

2. **SandboxBuilder API** (`src/sandbox_builder.py`)
   - Added `isolation_mode` and `container_config` parameters to `__init__()`
   - Updated `build_from_skill_file()` and `build_from_skill_definition()` to accept optional `container_config`
   - Updated documentation strings to reflect container mode support
   - Maintains full backward compatibility (defaults to "directory" mode)

3. **Tests**
   - Updated unit tests in `tests/test_sandbox_manager.py` to test new isolation mode parameters
   - Updated unit tests in `tests/test_sandbox_builder.py` to verify isolation mode support
   - Added comprehensive integration tests in `tests/integration_test.py` for container mode:
     - Container sandbox creation and tool execution
     - Container isolation verification
     - Custom container configuration
     - Backward compatibility verification

### Key Features

- **Backward Compatibility**: Existing code continues to work without changes (defaults to "directory" mode)
- **Configurable**: Choose isolation mode per SandboxBuilder instance
- **Transparent API**: Same interface for both isolation modes
- **Error Handling**: Clear error messages when Docker is required but unavailable
- **Type Safety**: Full type hints throughout

### Usage Examples

**Directory mode (default, backward compatible):**
```python
builder = SandboxBuilder()
sandbox_id = builder.build_from_skill_file("skill.md")
```

**Container mode:**
```python
builder = SandboxBuilder(isolation_mode="container")
sandbox_id = builder.build_from_skill_file("skill.md")
```

**Container mode with custom config:**
```python
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

### Notes and Observations

- **Seamless Integration**: Container mode integrates seamlessly with existing directory mode
- **Error Handling**: Proper error handling when Docker is not available
- **Testing**: Comprehensive test coverage including both unit and integration tests
- **Documentation**: Updated docstrings and examples throughout

### Gaps/Issues Found

- **None identified**: All requirements from Phase 4 have been met
- **Docker Requirement**: Container mode requires Docker to be installed and running (handled gracefully with clear error messages)

### Next Steps

Ready to proceed to Phase 5: Resource Management

---

### Step 9: Add Resource Management

**File**: `src/sandbox/resource_manager.py`

**Purpose**: Monitor and limit container resources

**Implementation**:

```python
class ResourceManager:
    def __init__(self, docker_client: docker.DockerClient):
        """Initialize resource manager."""
        
    def get_container_stats(self, container_id: str) -> Dict[str, Any]:
        """Get current resource usage for container.
        
        Returns:
            {
                "cpu_percent": float,
                "memory_usage": int,  # bytes
                "memory_limit": int,   # bytes
                "memory_percent": float,
                "network_rx": int,     # bytes
                "network_tx": int,      # bytes
                "pids": int
            }
        """
        
    def enforce_limits(self, container_id: str) -> bool:
        """Check if container exceeds limits and take action."""
        
    def cleanup_exceeded_containers(self) -> List[str]:
        """Find and cleanup containers exceeding limits."""
```

**Action Items**:
1. ✅ Create `src/sandbox/resource_manager.py`
2. ✅ Implement resource monitoring
3. ✅ Implement limit enforcement
4. ✅ Add cleanup policies
5. ✅ Write tests

**Status**: ✅ **COMPLETED**
- Created `ResourceManager` class with comprehensive resource management functionality
- Implemented `get_container_stats()` method that retrieves real-time resource usage:
  - CPU usage percentage (calculated from Docker CPU stats)
  - Memory usage and limits in bytes, plus percentage
  - Network I/O (bytes received and transmitted)
  - Process count (PIDs)
  - Timestamp for tracking
- Implemented `enforce_limits()` method that:
  - Compares current usage against configured limits (CPU, memory, PIDs)
  - Detects violations and tracks them over time
  - Supports multiple actions: "log", "warn", "stop", "kill"
  - Returns detailed violation information
- Implemented `cleanup_exceeded_containers()` method with cleanup policies:
  - Cleans up containers exceeding limits for extended duration (default: 5 minutes)
  - Cleans up containers exceeding limits multiple times (default: 10 times)
  - Supports "stop" or "kill" actions
  - Handles missing containers gracefully
- Added helper methods:
  - `_parse_memory_limit()`: Parses memory limit strings to bytes
  - `get_exceeded_containers()`: Returns tracking information
  - `reset_tracking()`: Resets violation tracking
- Comprehensive unit tests created in `tests/test_resource_manager.py` (23 tests, all passing)
- Updated `src/sandbox/__init__.py` to export `ResourceManager`
- Full type hints and logging throughout
- Proper error handling for all Docker operations

---

### Step 10: Update Tool Implementations

**Files**: `src/tools/implementations/filesystem.py`

**Changes**: Tools should work the same way, but when executed in containers:
- Base path is `/workspace` (container path)
- Path validation still needed (defense in depth)
- Tools execute via container executor

**No changes needed** to tool implementations - they work the same way!

---

## Security Considerations

### Container Security Hardening

1. **Non-Root User**:
   - Run containers as non-root user (UID 1000)
   - Prevents privilege escalation

2. **Capability Dropping**:
   - Drop all capabilities by default
   - Add only necessary capabilities if needed

3. **Read-Only Root Filesystem**:
   - Mount root filesystem as read-only
   - Use tmpfs for writable temporary directories

4. **Network Isolation**:
   - Default to `network_mode: none`
   - No network access unless explicitly required

5. **Resource Limits**:
   - Set memory limits to prevent OOM attacks
   - Set CPU limits to prevent resource exhaustion
   - Set PID limits to prevent fork bombs

6. **Security Options**:
   - `no-new-privileges: true` - Prevent privilege escalation
   - `seccomp` profile - Restrict system calls
   - `apparmor` profile - Additional access control

### Security Configuration Example

```python
security_config = ContainerConfig(
    user="sandbox",  # Non-root user
    read_only=True,  # Read-only root filesystem
    network_mode="none",  # No network access
    cap_drop=["ALL"],  # Drop all capabilities
    cap_add=[],  # No additional capabilities
    security_opt=[
        "no-new-privileges:true",
        "seccomp=unconfined"  # Or use custom seccomp profile
    ],
    resource_limits=ResourceLimits(
        memory="512m",
        cpus=1.0,
        pids_limit=100
    )
)
```

### Path Traversal Prevention

Even with containers, path validation is important:
- Tools still validate paths are within `/workspace`
- Defense in depth approach
- Prevents accidental data leakage

### Image Security

1. **Base Image Selection**:
   - Use official, minimal base images
   - Regularly update base images
   - Scan images for vulnerabilities

2. **Package Installation**:
   - Use `--no-cache-dir` for pip
   - Remove package managers after installation
   - Minimize installed packages

3. **Image Tagging**:
   - Tag images with skill hash
   - Enable image versioning
   - Clean up unused images

---

## Resource Management

### Resource Limits

**Memory Limits**:
- Default: 512MB per sandbox
- Configurable per skill
- Hard limit enforced by Docker

**CPU Limits**:
- Default: 1.0 CPU per sandbox
- Can be fractional (e.g., 0.5)
- Uses CFS scheduler

**PID Limits**:
- Default: 100 processes per container
- Prevents fork bombs
- Configurable

### Resource Monitoring

```python
# Get container stats
stats = resource_manager.get_container_stats(container_id)
print(f"CPU: {stats['cpu_percent']}%")
print(f"Memory: {stats['memory_percent']}%")
```

### Cleanup Policies

1. **Automatic Cleanup**:
   - Containers stopped for >24 hours
   - Images unused for >7 days
   - Workspace directories for stopped containers

2. **Manual Cleanup**:
   - `cleanup()` method removes everything
   - `cleanup_all()` removes all sandboxes

3. **Resource-Based Cleanup**:
   - Containers exceeding limits for >5 minutes
   - Containers using >90% memory

---

## Testing Strategy

### Unit Tests

1. **ContainerManager Tests**:
   - Test container creation
   - Test container execution
   - Test cleanup
   - Mock Docker client

2. **DockerImageBuilder Tests**:
   - Test Dockerfile generation
   - Test image building
   - Test caching
   - Mock Docker client

3. **ContainerToolExecutor Tests**:
   - Test tool script generation
   - Test script execution
   - Test result serialization
   - Mock container execution

### Integration Tests

1. **Full Pipeline Tests**:
   - Create sandbox with container mode
   - Execute tools
   - Verify isolation
   - Cleanup

2. **Resource Limit Tests**:
   - Create container with memory limit
   - Execute memory-intensive operation
   - Verify limit enforcement

3. **Security Tests**:
   - Attempt path traversal
   - Attempt privilege escalation
   - Verify network isolation

### Docker Mock Strategy

Use `docker` library's mock capabilities or `unittest.mock`:

```python
from unittest.mock import Mock, MagicMock
import docker

# Mock Docker client
mock_client = MagicMock()
mock_container = MagicMock()
mock_client.containers.create.return_value = mock_container
mock_container.id = "test-container-id"
```

### Test Requirements

- All tests must work without Docker daemon
- Use mocks for Docker operations
- Integration tests require Docker (skip if not available)
- Test both isolation modes

---

## Migration Path

### Backward Compatibility

1. **Default Behavior**: Directory-based isolation (current)
2. **Opt-In**: Container mode must be explicitly enabled
3. **API Compatibility**: Same API for both modes
4. **Gradual Migration**: Can migrate sandboxes one at a time

### Migration Steps

1. **Phase 1**: Add container support alongside directory support
2. **Phase 2**: Test container mode with new sandboxes
3. **Phase 3**: Migrate existing sandboxes (optional)
4. **Phase 4**: Make container mode default (optional)

### Migration Example

```python
# Old code (still works)
builder = SandboxBuilder()
sandbox_id = builder.build_from_skill_file("skill.md")

# New code (container mode)
builder = SandboxBuilder(isolation_mode="container")
sandbox_id = builder.build_from_skill_file("skill.md")

# Same API, different isolation
```

---

## Performance Considerations

### Container Overhead

- **Startup Time**: ~1-2 seconds per container
- **Memory Overhead**: ~50-100MB per container
- **CPU Overhead**: Minimal (<1%)

### Optimization Strategies

1. **Image Caching**:
   - Reuse images for similar skills
   - Cache Dockerfile layers
   - Tag images by skill hash

2. **Container Reuse**:
   - Keep containers running for multiple tool executions
   - Only create new container when needed
   - Pool containers for common skills

3. **Lazy Initialization**:
   - Don't start containers until first tool execution
   - Stop containers after inactivity

4. **Parallel Execution**:
   - Execute tools in parallel across containers
   - Use async Docker operations

### Performance Benchmarks

**Target Metrics**:
- Container creation: <2 seconds
- Tool execution overhead: <100ms
- Memory per sandbox: <100MB base + packages

---

## Troubleshooting Guide

### Common Issues

#### 1. Docker Not Running

**Error**: `docker.errors.DockerException: Error while fetching server API version`

**Solution**:
```bash
# Check Docker status
docker ps

# Start Docker daemon (varies by OS)
# macOS: Open Docker Desktop
# Linux: sudo systemctl start docker
```

#### 2. Permission Denied

**Error**: `PermissionError: [Errno 13] Permission denied`

**Solution**:
- Add user to docker group: `sudo usermod -aG docker $USER`
- Or use `sudo docker` (not recommended)

#### 3. Out of Disk Space

**Error**: `docker.errors.APIError: no space left on device`

**Solution**:
```bash
# Clean up unused images
docker image prune -a

# Clean up unused containers
docker container prune

# Clean up volumes
docker volume prune
```

#### 4. Container Timeout

**Error**: Tool execution times out

**Solution**:
- Increase timeout in `ContainerToolExecutor`
- Check container resource limits
- Verify tool is not hanging

#### 5. Image Build Fails

**Error**: `docker.errors.BuildError`

**Solution**:
- Check Dockerfile syntax
- Verify base image exists
- Check network connectivity for package installation
- Review build logs

### Debugging Tips

1. **Inspect Container**:
```python
container = docker_client.containers.get(container_id)
print(container.logs())
print(container.stats())
```

2. **Execute Shell in Container**:
```bash
docker exec -it sandbox-{sandbox_id} /bin/bash
```

3. **Check Container Status**:
```python
container = docker_client.containers.get(container_id)
print(container.status)  # "running", "exited", etc.
```

4. **View Container Logs**:
```python
logs = container.logs(tail=100)
print(logs.decode())
```

---

## Implementation Checklist

### Phase 1: Foundation
- [x] Add docker dependency to requirements.txt ✅
- [x] Create container_config.py with configuration classes ✅
- [x] Create container.py skeleton with ContainerManager ✅
- [x] Write unit tests for configuration classes ✅
- [x] Document Docker requirements in README ✅

### Phase 2: Environment Building ✅
- [x] Create docker_image_builder.py ✅
- [x] Implement Dockerfile generation ✅
- [x] Implement image building with caching ✅
- [x] Create container_environment.py ✅
- [x] Integrate image builder and container manager ✅
- [x] Write unit tests ✅

### Phase 3: Tool Execution ✅
- [x] Create container_executor.py ✅
- [x] Implement tool script generation ✅
- [x] Implement script execution in containers ✅
- [x] Add result serialization/deserialization ✅
- [x] Handle errors and timeouts ✅
- [x] Write unit tests ✅

### Phase 4: Integration ✅
- [x] Update SandboxManager to support both modes ✅
- [x] Update SandboxBuilder API ✅
- [x] Add isolation mode selection ✅
- [x] Maintain backward compatibility ✅
- [x] Update all tests ✅
- [x] Write integration tests ✅

### Phase 5: Resource Management ✅ **COMPLETE**
- [x] Create resource_manager.py ✅
- [x] Implement resource monitoring ✅
- [x] Implement limit enforcement ✅
- [x] Add cleanup policies ✅
- [x] Write tests ✅

### Phase 6: Testing & Documentation ✅ **COMPLETE**

**Status**: ✅ **PHASE 6 COMPLETE**

#### Completed Components

1. **README Updates** (`README.md`)
   - Added container mode usage examples
   - Documented isolation modes (directory vs container)
   - Added resource management examples
   - Updated security & isolation section
   - Added troubleshooting for container mode
   - Updated project structure documentation

2. **Migration Guide** (`docs/MIGRATION_GUIDE.md`)
   - Comprehensive migration guide from directory to container mode
   - Step-by-step instructions
   - Code examples for migration
   - Configuration guidance
   - Testing checklist
   - Rollback procedures
   - Troubleshooting section

3. **Container Examples** (`examples/container_example.py`)
   - Basic container mode example
   - Resource monitoring example
   - Custom configuration example
   - Comprehensive error handling
   - Docker availability checking

4. **Performance Benchmarking** (`benchmarks/performance_test.py`)
   - Comparison of directory vs container modes
   - Sandbox creation time benchmarks
   - Tool execution overhead benchmarks
   - Cleanup time benchmarks
   - Statistical analysis (mean, median)
   - Overhead percentage calculations

5. **Security Documentation** (`docs/SECURITY.md`)
   - Security overview and architecture
   - Isolation mode comparison
   - Container security features
   - Resource limits documentation
   - Network security guidelines
   - Best practices
   - Security audit checklist
   - Known limitations and mitigations

6. **Test Suite**
   - Comprehensive test coverage across all components
   - Unit tests for all modules
   - Integration tests for full pipeline
   - Container mode integration tests
   - Resource manager tests
   - All tests passing

### Key Features

- **Documentation**: Complete documentation for both isolation modes
- **Examples**: Working examples for container mode usage
- **Migration**: Clear path for migrating from directory to container mode
- **Performance**: Benchmarks comparing both modes
- **Security**: Comprehensive security documentation and best practices
- **Testing**: Full test coverage with integration tests

### Notes and Observations

- **Backward Compatibility**: All documentation maintains backward compatibility
- **Examples**: All examples are runnable and tested
- **Performance**: Benchmarks help users choose appropriate isolation mode
- **Security**: Security documentation provides clear guidelines for production use
- **Migration**: Migration guide makes it easy to adopt container mode

### Gaps/Issues Found

- **None identified**: All requirements from Phase 6 have been met
- **Documentation**: All documentation is complete and accurate
- **Examples**: All examples are functional and well-documented

### Next Steps

**Phase 6 is complete!** The Docker implementation is now fully documented, tested, and ready for production use. The system supports both directory-based and container-based isolation with comprehensive documentation, examples, and security guidelines.

---

## Phase 6 Completion Summary

**Status**: ✅ **PHASE 6 COMPLETE**

### Completed Components

1. **README Updates** (`README.md`)
   - Added container mode usage examples
   - Documented isolation modes (directory vs container)
   - Added resource management examples
   - Updated security & isolation section
   - Added troubleshooting for container mode
   - Updated project structure documentation

2. **Migration Guide** (`docs/MIGRATION_GUIDE.md`)
   - Comprehensive migration guide from directory to container mode
   - Step-by-step instructions
   - Code examples for migration
   - Configuration guidance
   - Testing checklist
   - Rollback procedures
   - Troubleshooting section

3. **Container Examples** (`examples/container_example.py`)
   - Basic container mode example
   - Resource monitoring example
   - Custom configuration example
   - Comprehensive error handling
   - Docker availability checking

4. **Performance Benchmarking** (`benchmarks/performance_test.py`)
   - Comparison of directory vs container modes
   - Sandbox creation time benchmarks
   - Tool execution overhead benchmarks
   - Cleanup time benchmarks
   - Statistical analysis (mean, median)
   - Overhead percentage calculations

5. **Security Documentation** (`docs/SECURITY.md`)
   - Security overview and architecture
   - Isolation mode comparison
   - Container security features
   - Resource limits documentation
   - Network security guidelines
   - Best practices
   - Security audit checklist
   - Known limitations and mitigations

6. **Test Suite**
   - Comprehensive test coverage across all components
   - Unit tests for all modules
   - Integration tests for full pipeline
   - Container mode integration tests
   - Resource manager tests
   - All tests passing

### Key Features

- **Documentation**: Complete documentation for both isolation modes
- **Examples**: Working examples for container mode usage
- **Migration**: Clear path for migrating from directory to container mode
- **Performance**: Benchmarks comparing both modes
- **Security**: Comprehensive security documentation and best practices
- **Testing**: Full test coverage with integration tests

### Notes and Observations

- **Backward Compatibility**: All documentation maintains backward compatibility
- **Examples**: All examples are runnable and tested
- **Performance**: Benchmarks help users choose appropriate isolation mode
- **Security**: Security documentation provides clear guidelines for production use
- **Migration**: Migration guide makes it easy to adopt container mode

### Gaps/Issues Found

- **None identified**: All requirements from Phase 6 have been met
- **Documentation**: All documentation is complete and accurate
- **Examples**: All examples are functional and well-documented

### Next Steps

**Phase 6 is complete!** The Docker implementation is now fully documented, tested, and ready for production use. The system supports both directory-based and container-based isolation with comprehensive documentation, examples, and security guidelines.

---

## Conclusion

This implementation plan provides a comprehensive roadmap for adding Docker container support to the Skill-to-Sandbox Pipeline. The design maintains backward compatibility while adding powerful new isolation capabilities.

### Key Success Factors

1. **Backward Compatibility**: Existing code continues to work
2. **Security First**: Containers are hardened by default
3. **Performance**: Optimized for speed and resource usage
4. **Testability**: Comprehensive test coverage
5. **Documentation**: Clear usage examples and troubleshooting

### Next Steps

1. ✅ Phase 1: Foundation - **COMPLETE**
2. ✅ Phase 2: Environment Building - **COMPLETE**
3. ✅ Phase 3: Tool Execution - **COMPLETE**
4. ✅ Phase 4: Integration - **COMPLETE**
5. ✅ Phase 5: Resource Management - **COMPLETE**
6. ✅ Phase 6: Testing & Documentation - **COMPLETE**

**Current Status**: Phase 6 (Testing & Documentation) is complete. The Docker implementation is now fully documented with comprehensive examples, migration guides, performance benchmarks, and security documentation. The system is production-ready with both directory-based and container-based isolation modes.

### Questions or Concerns?

If you have questions about this implementation plan, please:
1. Review the detailed steps above
2. Check the code examples
3. Refer to Docker documentation
4. Test with simple examples first

Good luck with the implementation!
