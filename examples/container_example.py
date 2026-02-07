#!/usr/bin/env python3
"""
Example usage of container-based sandbox isolation.

This script demonstrates:
1. Creating sandboxes with Docker containers
2. Configuring resource limits
3. Monitoring resource usage
4. Enforcing limits
5. Cleanup policies

Run this script from the project root directory.
Requires Docker to be installed and running.
"""

import sys
from pathlib import Path

# Add project root to Python path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits
from src.sandbox.resource_manager import ResourceManager

try:
    import docker
except ImportError:
    print("Error: docker package not installed. Install with: pip install docker>=6.0.0")
    sys.exit(1)


def example_basic_container():
    """Basic container mode example."""
    print("=" * 60)
    print("Basic Container Mode Example")
    print("=" * 60)
    print()
    
    # Configure container with resource limits
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
    
    # Create builder with container mode
    print("1. Creating SandboxBuilder with container isolation...")
    try:
        builder = SandboxBuilder(
            isolation_mode="container",
            container_config=config
        )
        print("   ✓ Builder created successfully")
    except RuntimeError as e:
        print(f"   ✗ Failed to create builder: {e}")
        print("   Make sure Docker is installed and running")
        return None
    print()
    
    # Build sandbox from skill file
    print("2. Building sandbox from skill file...")
    skill_path = PROJECT_ROOT / "examples" / "simple_skill.md"
    
    if not skill_path.exists():
        print(f"   ✗ Skill file not found: {skill_path}")
        return None
    
    try:
        sandbox_id = builder.build_from_skill_file(str(skill_path))
        print(f"   ✓ Sandbox created: {sandbox_id}")
    except Exception as e:
        print(f"   ✗ Failed to create sandbox: {e}")
        return None
    print()
    
    # Get sandbox info
    print("3. Getting sandbox information...")
    try:
        info = builder.get_sandbox_info(sandbox_id)
        if info:
            print(f"   ✓ Isolation Mode: {info.get('isolation_mode', 'unknown')}")
            print(f"   ✓ Container ID: {info.get('container_id', 'N/A')}")
            print(f"   ✓ Available Tools: {', '.join(info.get('tools', []))}")
    except Exception as e:
        print(f"   ✗ Failed to get sandbox info: {e}")
    print()
    
    # Execute tools
    print("4. Executing tools in container...")
    try:
        # Write file
        result = builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="container_test.txt",
            content="Hello from Docker container!\nThis file was created inside a container."
        )
        print(f"   ✓ File written: {result.get('file_path', 'unknown')}")
        
        # Read file
        content = builder.execute_in_sandbox(
            sandbox_id,
            "read_file",
            file_path="container_test.txt"
        )
        print(f"   ✓ File content: {content[:50]}...")
        
        # List files
        files = builder.execute_in_sandbox(
            sandbox_id,
            "list_files",
            directory_path="."
        )
        print(f"   ✓ Found {len(files)} files in workspace")
    except Exception as e:
        print(f"   ✗ Tool execution failed: {e}")
    print()
    
    # Cleanup
    print("5. Cleaning up sandbox...")
    try:
        builder.cleanup(sandbox_id)
        print(f"   ✓ Sandbox {sandbox_id} cleaned up")
    except Exception as e:
        print(f"   ✗ Cleanup failed: {e}")
    print()
    
    return sandbox_id


def example_resource_monitoring():
    """Example of resource monitoring and limit enforcement."""
    print("=" * 60)
    print("Resource Monitoring Example")
    print("=" * 60)
    print()
    
    # Configure container
    config = ContainerConfig(
        resource_limits=ResourceLimits(
            memory="256m",      # 256 MB (smaller for demo)
            cpus=0.5,           # 0.5 CPU cores
            pids_limit=50
        )
    )
    
    # Create builder
    print("1. Creating sandbox...")
    try:
        builder = SandboxBuilder(
            isolation_mode="container",
            container_config=config
        )
        skill_path = PROJECT_ROOT / "examples" / "simple_skill.md"
        sandbox_id = builder.build_from_skill_file(str(skill_path))
        print(f"   ✓ Sandbox created: {sandbox_id}")
    except Exception as e:
        print(f"   ✗ Failed to create sandbox: {e}")
        return
    print()
    
    # Get container ID from sandbox info
    try:
        info = builder.get_sandbox_info(sandbox_id)
        container_id = info.get('container_id')
        if not container_id:
            print("   ✗ Container ID not found")
            builder.cleanup(sandbox_id)
            return
    except Exception as e:
        print(f"   ✗ Failed to get container ID: {e}")
        builder.cleanup(sandbox_id)
        return
    
    # Initialize resource manager
    print("2. Initializing ResourceManager...")
    try:
        docker_client = docker.from_env()
        resource_manager = ResourceManager(docker_client, default_config=config)
        print("   ✓ ResourceManager initialized")
    except Exception as e:
        print(f"   ✗ Failed to initialize ResourceManager: {e}")
        builder.cleanup(sandbox_id)
        return
    print()
    
    # Get container stats
    print("3. Getting container resource stats...")
    try:
        stats = resource_manager.get_container_stats(container_id)
        print(f"   ✓ CPU Usage: {stats['cpu_percent']}%")
        print(f"   ✓ Memory Usage: {stats['memory_usage'] / 1024 / 1024:.2f} MB ({stats['memory_percent']}%)")
        print(f"   ✓ Memory Limit: {stats['memory_limit'] / 1024 / 1024:.2f} MB")
        print(f"   ✓ Processes: {stats['pids']}")
        print(f"   ✓ Network RX: {stats['network_rx']} bytes")
        print(f"   ✓ Network TX: {stats['network_tx']} bytes")
    except Exception as e:
        print(f"   ✗ Failed to get stats: {e}")
    print()
    
    # Enforce limits
    print("4. Enforcing resource limits...")
    try:
        result = resource_manager.enforce_limits(
            container_id,
            action_on_exceed="warn"  # Options: "log", "warn", "stop", "kill"
        )
        
        if result["exceeded"]:
            print(f"   ⚠ Limits exceeded!")
            for violation in result["violations"]:
                print(f"      - {violation}")
            print(f"   Action taken: {result['action_taken']}")
        else:
            print(f"   ✓ All limits within bounds")
    except Exception as e:
        print(f"   ✗ Failed to enforce limits: {e}")
    print()
    
    # Cleanup
    print("5. Cleaning up...")
    try:
        builder.cleanup(sandbox_id)
        print(f"   ✓ Sandbox cleaned up")
    except Exception as e:
        print(f"   ✗ Cleanup failed: {e}")
    print()


def example_custom_configuration():
    """Example with custom container configuration."""
    print("=" * 60)
    print("Custom Configuration Example")
    print("=" * 60)
    print()
    
    # Custom configuration for production use
    config = ContainerConfig(
        base_image="python:3.11-slim",
        resource_limits=ResourceLimits(
            memory="1g",         # 1 GB memory
            cpus=2.0,            # 2 CPU cores
            pids_limit=200       # Max 200 processes
        ),
        network_mode="none",     # No network access
        read_only=True,          # Read-only root filesystem
        environment_vars={
            "PYTHONUNBUFFERED": "1",
            "PYTHONPATH": "/workspace"
        },
        working_dir="/workspace",
        user="sandbox:1000",     # Run as non-root user
        cap_drop=["ALL"],        # Drop all capabilities
        security_opt=["no-new-privileges:true"]
    )
    
    print("1. Configuration:")
    print(f"   Base Image: {config.base_image}")
    print(f"   Memory Limit: {config.resource_limits.memory}")
    print(f"   CPU Limit: {config.resource_limits.cpus}")
    print(f"   Network Mode: {config.network_mode}")
    print(f"   Read-Only: {config.read_only}")
    print()
    
    # Create builder
    print("2. Creating sandbox with custom config...")
    try:
        builder = SandboxBuilder(
            isolation_mode="container",
            container_config=config
        )
        skill_path = PROJECT_ROOT / "examples" / "simple_skill.md"
        sandbox_id = builder.build_from_skill_file(str(skill_path))
        print(f"   ✓ Sandbox created: {sandbox_id}")
    except Exception as e:
        print(f"   ✗ Failed to create sandbox: {e}")
        return
    print()
    
    # Execute tools
    print("3. Executing tools...")
    try:
        result = builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="config_test.txt",
            content="Created with custom configuration"
        )
        print(f"   ✓ Tool executed successfully")
    except Exception as e:
        print(f"   ✗ Tool execution failed: {e}")
    print()
    
    # Cleanup
    print("4. Cleaning up...")
    try:
        builder.cleanup(sandbox_id)
        print(f"   ✓ Sandbox cleaned up")
    except Exception as e:
        print(f"   ✗ Cleanup failed: {e}")
    print()


def main():
    """Run all examples."""
    print("\n" + "=" * 60)
    print("Container Mode Examples")
    print("=" * 60)
    print()
    
    # Check Docker availability
    try:
        docker_client = docker.from_env()
        docker_client.ping()
        print("✓ Docker is available and running")
    except Exception as e:
        print(f"✗ Docker is not available: {e}")
        print("  Please install Docker and ensure it's running")
        print("  See: https://docs.docker.com/get-docker/")
        return
    print()
    
    # Run examples
    try:
        example_basic_container()
        print()
        
        example_resource_monitoring()
        print()
        
        example_custom_configuration()
        print()
        
        print("=" * 60)
        print("All examples completed!")
        print("=" * 60)
    except KeyboardInterrupt:
        print("\n\nExamples interrupted by user")
    except Exception as e:
        print(f"\n\nError running examples: {e}")
        import traceback
        traceback.print_exc()


if __name__ == "__main__":
    main()
