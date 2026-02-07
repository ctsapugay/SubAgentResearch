# Skill-to-Sandbox Pipeline

A system for automatically converting skill/subagent definitions into isolated, executable sandbox environments. This is Part 1 of the subagent research project, focused on creating the infrastructure to generate training data for small specialized models.

## Overview

This project solves the problem: **"How do we get from a skill/subagent definition to a working sandbox?"**

Given a skill definition (like a SKILL.md file), this system:
1. Parses the skill to understand its requirements
2. Creates an isolated sandbox environment
3. Sets up all necessary tools
4. Provides a safe execution environment for generating training data

## What is a Skill/Subagent?

A skill/subagent is a specialized AI agent designed for a specific task. It includes:
- **System prompt**: Instructions defining the agent's role
- **Tools**: Available actions (e.g., `web_search`, `read_file`, `codebase_search`)
- **Environment requirements**: Dependencies needed (Python version, packages, etc.)

Example: A "React.js Researcher" skill might have tools like `web_search` and `read_file`, with instructions to research and summarize React.js information.

## What is a Sandbox?

A sandbox is an isolated, controlled environment where:
- Skills can execute safely without affecting your system
- Tools are available and properly configured
- You can test skills and generate training data
- Each sandbox is completely separate from others

## Architecture

```
┌─────────────────┐
│  SKILL.md File  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Skill Parser   │  ← Reads and extracts skill definition
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│ Sandbox Builder │  ← Main orchestrator
└────────┬────────┘
         │
         ├──────────────┬──────────────┐
         ▼              ▼              ▼
┌──────────────┐ ┌──────────────┐ ┌──────────────┐
│ Environment  │ │   Tool       │ │   Sandbox    │
│   Builder    │ │  Registry    │ │   Manager    │
└──────────────┘ └──────────────┘ └──────────────┘
         │              │              │
         └──────────────┴──────────────┘
                        │
                        ▼
              ┌─────────────────┐
              │  Working        │
              │  Sandbox        │
              └─────────────────┘
```

### Components

1. **Skill Parser** (`src/skill_parser/`)
   - Reads SKILL.md files
   - Extracts name, description, system prompt, tools, requirements
   - Converts to structured `SkillDefinition` object

2. **Tool Registry** (`src/tools/`)
   - Catalog of available tool implementations
   - Manages tool instantiation
   - Provides tool schemas and validation

3. **Environment Builder** (`src/sandbox/environment.py`)
   - Creates isolated directory structures
   - Sets up Python virtual environments
   - Installs required packages
   - Configures workspace

4. **Sandbox Manager** (`src/sandbox/manager.py`)
   - Manages sandbox lifecycle (create, use, cleanup)
   - Tracks active sandboxes
   - Executes tools within sandboxes
   - Handles isolation and security

5. **Sandbox Builder** (`src/sandbox_builder.py`)
   - Main public interface
   - Coordinates all components
   - Provides simple API for users

## Installation

### Prerequisites

- Python 3.11 or higher
- pip or uv package manager
- Docker (optional, for container-based sandbox isolation)
  - Docker Desktop for macOS/Windows: https://www.docker.com/products/docker-desktop
  - Docker Engine for Linux: https://docs.docker.com/engine/install/

### Setup

1. Clone the repository:
```bash
cd "/Users/clara/Desktop/main/ucsc/WangLab/Subagent Research"
```

2. Install dependencies:
```bash
pip install -r requirements.txt
```

Or using uv:
```bash
uv pip install -r requirements.txt
```

**Note**: If you plan to use Docker container support (optional), ensure Docker is installed and running:
```bash
# Verify Docker installation
docker --version

# Check Docker daemon is running
docker ps
```

If Docker is not available, the system will use directory-based isolation (default).

## Usage

### Isolation Modes

The system supports two isolation modes:

1. **Directory-based isolation** (default): Uses directory separation and Python virtual environments
   - Faster startup time
   - Lower resource overhead
   - Suitable for trusted code
   - No Docker required

2. **Container-based isolation**: Uses Docker containers for stronger isolation
   - Enhanced security with OS-level isolation
   - Resource limits (CPU, memory, PIDs)
   - Network isolation
   - Suitable for untrusted code
   - Requires Docker

### Basic Example (Directory Mode)

```python
from src.sandbox_builder import SandboxBuilder

# Initialize the builder
builder = SandboxBuilder()

# Build a sandbox from a skill file
skill_path = "examples/example_skill.md"
sandbox_id = builder.build_from_skill_file(skill_path)

print(f"Created sandbox: {sandbox_id}")

# Get information about the sandbox
info = builder.get_sandbox_info(sandbox_id)
print(f"Available tools: {list(info['tools'].keys())}")

# Execute a tool in the sandbox
result = builder.execute_in_sandbox(
    sandbox_id,
    "write_file",
    file_path="test.txt",
    content="Hello, sandbox!"
)

# Read the file back
content = builder.execute_in_sandbox(
    sandbox_id,
    "read_file",
    file_path="test.txt"
)
print(f"Content: {content}")

# Clean up when done
builder.cleanup(sandbox_id)
```

### Working with Skill Definitions

```python
from src.skill_parser.parser import SkillParser
from src.sandbox_builder import SandboxBuilder

# Parse a skill manually
parser = SkillParser()
skill = parser.parse("path/to/skill.md")

# Inspect the skill
print(f"Skill: {skill.name}")
print(f"Description: {skill.description}")
print(f"Tools: {skill.get_tool_names()}")
print(f"Requirements: {skill.environment_requirements}")

# Build sandbox from parsed skill
builder = SandboxBuilder()
sandbox_id = builder.build_from_skill_definition(skill)
```

### Managing Multiple Sandboxes

```python
from src.sandbox_builder import SandboxBuilder

builder = SandboxBuilder()

# Create multiple sandboxes
sandbox1 = builder.build_from_skill_file("skill1.md")
sandbox2 = builder.build_from_skill_file("skill2.md")

# Each sandbox is isolated
builder.execute_in_sandbox(sandbox1, "write_file", 
                          file_path="test.txt", content="Sandbox 1")
builder.execute_in_sandbox(sandbox2, "write_file", 
                          file_path="test.txt", content="Sandbox 2")

# Files don't interfere with each other
content1 = builder.execute_in_sandbox(sandbox1, "read_file", 
                                      file_path="test.txt")
content2 = builder.execute_in_sandbox(sandbox2, "read_file", 
                                      file_path="test.txt")

print(content1)  # "Sandbox 1"
print(content2)  # "Sandbox 2"

# Clean up
builder.cleanup(sandbox1)
builder.cleanup(sandbox2)
```

### Container Mode Example

```python
from src.sandbox_builder import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

# Initialize builder with container isolation
config = ContainerConfig(
    base_image="python:3.11-slim",
    resource_limits=ResourceLimits(
        memory="512m",      # 512 MB memory limit
        cpus=1.0,           # 1 CPU core
        pids_limit=100      # Max 100 processes
    ),
    network_mode="none",    # No network access
    read_only=True          # Read-only root filesystem
)

builder = SandboxBuilder(
    isolation_mode="container",
    container_config=config
)

# Build sandbox (creates Docker container)
sandbox_id = builder.build_from_skill_file("examples/example_skill.md")

# Execute tools (runs inside container)
result = builder.execute_in_sandbox(
    sandbox_id,
    "write_file",
    file_path="test.txt",
    content="Hello from container!"
)

# Monitor resource usage
from src.sandbox.resource_manager import ResourceManager
import docker

docker_client = docker.from_env()
resource_manager = ResourceManager(docker_client, default_config=config)

stats = resource_manager.get_container_stats(sandbox_id)
print(f"CPU: {stats['cpu_percent']}%, Memory: {stats['memory_percent']}%")

# Enforce limits
enforcement = resource_manager.enforce_limits(sandbox_id, action_on_exceed="warn")
if enforcement["exceeded"]:
    print(f"Warning: {enforcement['violations']}")

# Cleanup
builder.cleanup(sandbox_id)
```

### Resource Management

Monitor and enforce resource limits for container-based sandboxes:

```python
from src.sandbox.resource_manager import ResourceManager
from src.sandbox.container_config import ContainerConfig, ResourceLimits
import docker

docker_client = docker.from_env()
config = ContainerConfig(
    resource_limits=ResourceLimits(memory="512m", cpus=1.0, pids_limit=100)
)
resource_manager = ResourceManager(docker_client, default_config=config)

# Get container stats
stats = resource_manager.get_container_stats(container_id)
print(f"CPU Usage: {stats['cpu_percent']}%")
print(f"Memory Usage: {stats['memory_usage']} bytes ({stats['memory_percent']}%)")
print(f"Processes: {stats['pids']}")

# Enforce limits with automatic action
result = resource_manager.enforce_limits(
    container_id,
    action_on_exceed="stop"  # Options: "log", "warn", "stop", "kill"
)

# Cleanup containers exceeding limits
cleaned = resource_manager.cleanup_exceeded_containers(
    exceeded_duration=300,      # 5 minutes
    max_exceeded_count=10,      # 10 violations
    action="stop"
)
```

## Skill File Format

Skills are defined in Markdown files (SKILL.md). The parser looks for:

### Required Sections

- **Title**: First `#` heading becomes the skill name
- **Description**: First paragraph or `## Description` section
- **System Prompt**: `## System Prompt` or `## Instructions` section

### Optional Sections

- **Tools**: `## Tools` section listing available tools
- **Requirements**: `## Requirements` or `## Environment` section

### Example Skill File

```markdown
# Web Research Assistant

## Description
An AI assistant specialized in researching topics on the web and summarizing findings.

## System Prompt
You are a web research assistant. Your role is to:
- Search the web for relevant information
- Read and analyze content
- Provide concise summaries
- Cite your sources

## Tools
- web_search: Search the web for information
- read_file: Read files from the workspace
- write_file: Write summaries to files

## Requirements
- Python 3.11
- requests
- beautifulsoup4
```

## Available Tools

### Filesystem Tools

- **`read_file(file_path)`**: Read content from a file
- **`write_file(file_path, content)`**: Write content to a file
- **`list_files(directory_path=".")`**: List files in a directory

### Adding Custom Tools

To add a new tool:

1. Create a tool class inheriting from `ToolBase`:
```python
from src.tools.base import ToolBase

class MyCustomTool(ToolBase):
    def __init__(self):
        super().__init__("my_tool", "Description of my tool")
    
    def validate_parameters(self, **kwargs) -> bool:
        return "param1" in kwargs
    
    def execute(self, **kwargs):
        # Your tool logic here
        return {"result": "success"}
```

2. Register it in `ToolRegistry`:
```python
from src.tools.registry import ToolRegistry

registry = ToolRegistry()
registry.register("my_tool", MyCustomTool)
```

## How It Works

### Step 1: Parse Skill
The `SkillParser` reads a SKILL.md file and extracts:
- Skill name and description
- System prompt/instructions
- List of required tools
- Environment requirements (Python version, packages)

### Step 2: Create Environment
The `EnvironmentBuilder`:
- Creates a unique sandbox directory
- Sets up workspace structure
- Creates Python virtual environment (if needed)
- Installs required packages
- Saves skill metadata

### Step 3: Initialize Tools
The `ToolRegistry`:
- Looks up each required tool
- Instantiates tool objects with sandbox workspace path
- Makes tools available for execution

### Step 4: Sandbox Ready
The `SandboxManager`:
- Tracks the sandbox with a unique ID
- Provides tool execution interface
- Ensures isolation between sandboxes

### Step 5: Execute Tools
When you call `execute_in_sandbox()`:
- Tool is looked up in the sandbox's tool registry
- Parameters are validated
- Tool executes within the sandbox's workspace
- Results are returned

## Security & Isolation

### Directory Mode
- **Path Isolation**: All file operations are restricted to the sandbox workspace
- **Separate Environments**: Each sandbox has its own directory and virtual environment
- **No System Access**: Tools cannot access files outside the sandbox
- **Cleanup**: Sandboxes can be completely removed when done

### Container Mode
- **OS-Level Isolation**: Containers provide process and filesystem isolation
- **Resource Limits**: CPU, memory, and process limits enforced by Docker
- **Network Isolation**: Containers can run with no network access (`network_mode="none"`)
- **Read-Only Filesystem**: Root filesystem can be mounted read-only for additional security
- **Capability Dropping**: Containers run with minimal Linux capabilities
- **Non-Root User**: Containers run as non-root user by default
- **Security Options**: Additional hardening options available (seccomp, AppArmor)

See [docs/SECURITY.md](docs/SECURITY.md) for detailed security documentation.

## Project Structure

```
Subagent Research/
├── src/
│   ├── skill_parser/
│   │   ├── __init__.py
│   │   ├── parser.py              # Parses SKILL.md files
│   │   └── skill_definition.py    # Data structures
│   ├── sandbox/
│   │   ├── __init__.py
│   │   ├── manager.py             # Sandbox lifecycle
│   │   ├── container.py           # Docker container management
│   │   ├── container_config.py    # Container configuration
│   │   ├── container_environment.py # Container environment builder
│   │   ├── container_executor.py  # Tool execution in containers
│   │   ├── docker_image_builder.py # Docker image building
│   │   ├── resource_manager.py   # Resource monitoring and limits
│   │   └── environment.py        # Environment setup
│   ├── tools/
│   │   ├── __init__.py
│   │   ├── registry.py            # Tool catalog
│   │   ├── base.py                # Tool interface
│   │   └── implementations/
│   │       ├── filesystem.py      # File operations
│   │       ├── web_search.py      # Web search (future)
│   │       └── codebase_search.py # Code search (future)
│   └── sandbox_builder.py         # Main interface
├── tests/                          # Test files
├── examples/                       # Example skills
├── sandboxes/                      # Created sandboxes (auto-generated)
├── requirements.txt
└── README.md
```

## Testing

Run tests with:
```bash
pytest tests/
```

Run with coverage:
```bash
pytest tests/ --cov=src --cov-report=html
```

## Next Steps

This is Part 1 of the research project. Future work includes:

1. **Part 2**: Generate synthetic training data using sandboxes
2. **Part 3**: Train small models on the generated data
3. **Part 4**: Evaluate trained models against benchmarks

## Contributing

When adding new features:
1. Add tests in `tests/`
2. Update this README
3. Follow existing code style
4. Ensure all tests pass

## Troubleshooting

### Sandbox creation fails
- Check that Python 3.11+ is installed
- Verify write permissions in the sandbox directory
- Check that required packages can be installed
- For container mode: Ensure Docker is installed and running (`docker ps`)

### Tool execution errors
- Verify the tool is registered in `ToolRegistry`
- Check tool parameter validation
- Ensure file paths are within the sandbox workspace
- For container mode: Check container logs with `docker logs sandbox-{sandbox_id}`

### Import errors
- Make sure all dependencies are installed: `pip install -r requirements.txt`
- Verify Python path includes the project root

### Container mode issues
- **Docker not running**: Start Docker Desktop or Docker daemon
- **Permission denied**: Add user to docker group: `sudo usermod -aG docker $USER`
- **Out of disk space**: Clean up unused images: `docker image prune -a`
- **Container timeout**: Increase timeout in `ContainerToolExecutor` or check resource limits

See [docs/DOCKER_IMPLEMENTATION_PLAN.md](docs/DOCKER_IMPLEMENTATION_PLAN.md) for detailed troubleshooting.

## Migration Guide

Migrating from directory-based to container-based isolation? See [docs/MIGRATION_GUIDE.md](docs/MIGRATION_GUIDE.md) for step-by-step instructions.

## License

[Add your license here]

## Contact

[Add contact information]
