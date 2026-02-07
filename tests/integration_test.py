"""Integration tests for the full skill-to-sandbox pipeline."""

import tempfile
from pathlib import Path

import pytest

from src.sandbox.container_config import ContainerConfig, ResourceLimits
from src.sandbox_builder import SandboxBuilder

# Check if Docker is available
try:
    import docker
    docker_client = docker.from_env()
    docker_client.ping()
    DOCKER_AVAILABLE = True
except Exception:
    DOCKER_AVAILABLE = False


@pytest.fixture
def temp_dir():
    """Create a temporary directory for tests."""
    with tempfile.TemporaryDirectory() as tmpdir:
        yield tmpdir


@pytest.fixture
def builder(temp_dir):
    """Create a SandboxBuilder instance with temporary directory."""
    return SandboxBuilder(sandbox_base_path=temp_dir)


@pytest.fixture
def example_skill_file():
    """Path to the example skill file."""
    return Path(__file__).parent.parent / "examples" / "example_skill.md"


@pytest.fixture
def simple_skill_file():
    """Path to a simple skill file without packages."""
    return Path(__file__).parent.parent / "examples" / "simple_skill.md"


@pytest.fixture
def complex_skill_file():
    """Path to the complex skill file."""
    return Path(__file__).parent.parent / "examples" / "complex_skill.md"


class TestFullPipeline:
    """Test the complete skill-to-sandbox pipeline."""
    
    def test_build_and_use_sandbox_from_file(self, builder, simple_skill_file):
        """Test building a sandbox from a skill file and using it."""
        # Build sandbox from file (using simple skill without packages to avoid network issues)
        sandbox_id = builder.build_from_skill_file(str(simple_skill_file))
        assert sandbox_id is not None
        
        # Get sandbox info
        info = builder.get_sandbox_info(sandbox_id)
        assert info is not None
        assert info["skill_name"] == "Simple Test Skill"
        assert "read_file" in info["tools"]
        assert "write_file" in info["tools"]
        
        # Execute tools
        write_result = builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="summary.txt",
            content="This is a test summary."
        )
        assert write_result is not None
        
        # Read the file back
        content = builder.execute_in_sandbox(
            sandbox_id,
            "read_file",
            file_path="summary.txt"
        )
        assert "test summary" in content
        
        # List files
        files = builder.execute_in_sandbox(
            sandbox_id,
            "list_files",
            directory_path="."
        )
        assert isinstance(files, list)
        assert "summary.txt" in files
        
        # Cleanup
        assert builder.cleanup(sandbox_id) is True
        assert builder.get_sandbox_info(sandbox_id) is None
    
    def test_build_with_packages_if_network_available(self, builder, example_skill_file):
        """Test building a sandbox with packages if network is available."""
        # Try to build with packages, but skip if network is not available
        try:
            sandbox_id = builder.build_from_skill_file(str(example_skill_file))
            assert sandbox_id is not None
            
            info = builder.get_sandbox_info(sandbox_id)
            assert info is not None
            assert info["skill_name"] == "Web Research Assistant"
            
            # Cleanup
            builder.cleanup(sandbox_id)
        except RuntimeError as e:
            if "Failed to install packages" in str(e) or "network" in str(e).lower():
                pytest.skip("Network access required for package installation")
            raise
    
    def test_multiple_sandboxes_isolation(self, builder, simple_skill_file):
        """Test that multiple sandboxes are isolated from each other."""
        # Create two sandboxes
        sandbox_id1 = builder.build_from_skill_file(str(simple_skill_file))
        sandbox_id2 = builder.build_from_skill_file(str(simple_skill_file))
        
        assert sandbox_id1 != sandbox_id2
        
        # Write different files in each sandbox
        builder.execute_in_sandbox(
            sandbox_id1,
            "write_file",
            file_path="file1.txt",
            content="Sandbox 1 content"
        )
        
        builder.execute_in_sandbox(
            sandbox_id2,
            "write_file",
            file_path="file1.txt",
            content="Sandbox 2 content"
        )
        
        # Verify isolation - each sandbox has its own file
        content1 = builder.execute_in_sandbox(
            sandbox_id1,
            "read_file",
            file_path="file1.txt"
        )
        assert "Sandbox 1 content" in content1
        
        content2 = builder.execute_in_sandbox(
            sandbox_id2,
            "read_file",
            file_path="file1.txt"
        )
        assert "Sandbox 2 content" in content2
        
        # Cleanup
        builder.cleanup(sandbox_id1)
        builder.cleanup(sandbox_id2)
    
    def test_complex_skill_parsing(self, builder, complex_skill_file):
        """Test parsing and using a complex skill file."""
        if not complex_skill_file.exists():
            pytest.skip("Complex skill file not found")
        
        # Build sandbox from complex skill
        # Note: This may fail if network access is not available for package installation
        try:
            sandbox_id = builder.build_from_skill_file(str(complex_skill_file))
            assert sandbox_id is not None
        except RuntimeError as e:
            if "Failed to install packages" in str(e) or "network" in str(e).lower():
                pytest.skip("Network access required for package installation")
            raise
        
        # Get info
        info = builder.get_sandbox_info(sandbox_id)
        assert info is not None
        
        # Verify tools are available
        tools = builder.list_tools(sandbox_id)
        assert len(tools) > 0
        
        # Cleanup
        builder.cleanup(sandbox_id)
    
    def test_sandbox_workflow(self, builder, simple_skill_file):
        """Test a typical sandbox workflow."""
        # 1. Build sandbox
        sandbox_id = builder.build_from_skill_file(str(simple_skill_file))
        
        # 2. Check available tools
        tools = builder.list_tools(sandbox_id)
        assert len(tools) > 0
        
        # 3. Create some files
        builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="data.txt",
            content="Some data"
        )
        
        builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="results.txt",
            content="Results here"
        )
        
        # 4. List files
        files = builder.execute_in_sandbox(
            sandbox_id,
            "list_files",
            directory_path="."
        )
        assert "data.txt" in files
        assert "results.txt" in files
        
        # 5. Read files
        data_content = builder.execute_in_sandbox(
            sandbox_id,
            "read_file",
            file_path="data.txt"
        )
        assert "Some data" in data_content
        
        # 6. Cleanup
        builder.cleanup(sandbox_id)
    
    def test_error_handling(self, builder, simple_skill_file):
        """Test error handling in the pipeline."""
        sandbox_id = builder.build_from_skill_file(str(simple_skill_file))
        
        # Try to read nonexistent file
        with pytest.raises(Exception):  # FileNotFoundError or RuntimeError
            builder.execute_in_sandbox(
                sandbox_id,
                "read_file",
                file_path="nonexistent.txt"
            )
        
        # Try to execute tool in nonexistent sandbox
        with pytest.raises(ValueError, match="not found"):
            builder.execute_in_sandbox(
                "nonexistent-id",
                "read_file",
                file_path="test.txt"
            )
        
        # Cleanup
        builder.cleanup(sandbox_id)
    
    def test_cleanup_all_after_multiple_sandboxes(self, builder, simple_skill_file):
        """Test cleanup_all with multiple sandboxes."""
        # Create multiple sandboxes
        sandbox_ids = []
        for _ in range(3):
            sandbox_id = builder.build_from_skill_file(str(simple_skill_file))
            sandbox_ids.append(sandbox_id)
        
        # Verify they all exist
        for sandbox_id in sandbox_ids:
            assert builder.get_sandbox_info(sandbox_id) is not None
        
        # Cleanup all
        count = builder.cleanup_all()
        assert count == 3
        
        # Verify they're all gone
        for sandbox_id in sandbox_ids:
            assert builder.get_sandbox_info(sandbox_id) is None


@pytest.mark.skipif(not DOCKER_AVAILABLE, reason="Docker not available")
class TestContainerModeIntegration:
    """Integration tests for container isolation mode."""
    
    @pytest.fixture
    def container_builder(self, temp_dir):
        """Create a SandboxBuilder instance with container isolation."""
        return SandboxBuilder(
            sandbox_base_path=temp_dir,
            isolation_mode="container"
        )
    
    def test_build_sandbox_with_container_mode(self, container_builder, simple_skill_file):
        """Test building a sandbox with container isolation mode."""
        sandbox_id = container_builder.build_from_skill_file(str(simple_skill_file))
        assert sandbox_id is not None
        
        # Get sandbox info
        info = container_builder.get_sandbox_info(sandbox_id)
        assert info is not None
        assert info["isolation_mode"] == "container"
        assert "container_id" in info
        assert info["container_id"] is not None
        
        # Cleanup
        assert container_builder.cleanup(sandbox_id) is True
    
    def test_execute_tools_in_container(self, container_builder, simple_skill_file):
        """Test executing tools within a container."""
        sandbox_id = container_builder.build_from_skill_file(str(simple_skill_file))
        
        # Write a file
        write_result = container_builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="test.txt",
            content="Hello from container!"
        )
        assert write_result is not None
        
        # Read the file back
        content = container_builder.execute_in_sandbox(
            sandbox_id,
            "read_file",
            file_path="test.txt"
        )
        assert "Hello from container!" in content
        
        # Cleanup
        container_builder.cleanup(sandbox_id)
    
    def test_container_isolation(self, container_builder, simple_skill_file):
        """Test that containers provide isolation."""
        # Create two sandboxes
        sandbox_id1 = container_builder.build_from_skill_file(str(simple_skill_file))
        sandbox_id2 = container_builder.build_from_skill_file(str(simple_skill_file))
        
        assert sandbox_id1 != sandbox_id2
        
        # Write different files in each sandbox
        container_builder.execute_in_sandbox(
            sandbox_id1,
            "write_file",
            file_path="file.txt",
            content="Container 1"
        )
        
        container_builder.execute_in_sandbox(
            sandbox_id2,
            "write_file",
            file_path="file.txt",
            content="Container 2"
        )
        
        # Verify isolation
        content1 = container_builder.execute_in_sandbox(
            sandbox_id1,
            "read_file",
            file_path="file.txt"
        )
        assert "Container 1" in content1
        
        content2 = container_builder.execute_in_sandbox(
            sandbox_id2,
            "read_file",
            file_path="file.txt"
        )
        assert "Container 2" in content2
        
        # Cleanup
        container_builder.cleanup(sandbox_id1)
        container_builder.cleanup(sandbox_id2)
    
    def test_container_with_custom_config(self, temp_dir, simple_skill_file):
        """Test container mode with custom configuration."""
        config = ContainerConfig(
            base_image="python:3.11-slim",
            resource_limits=ResourceLimits(
                memory="256m",
                cpus=0.5
            )
        )
        
        builder = SandboxBuilder(
            sandbox_base_path=temp_dir,
            isolation_mode="container",
            container_config=config
        )
        
        sandbox_id = builder.build_from_skill_file(str(simple_skill_file))
        assert sandbox_id is not None
        
        # Verify it works
        builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="test.txt",
            content="Test"
        )
        
        # Cleanup
        builder.cleanup(sandbox_id)
    
    def test_backward_compatibility_directory_mode(self, temp_dir, simple_skill_file):
        """Test that directory mode still works (backward compatibility)."""
        builder = SandboxBuilder(
            sandbox_base_path=temp_dir,
            isolation_mode="directory"
        )
        
        sandbox_id = builder.build_from_skill_file(str(simple_skill_file))
        assert sandbox_id is not None
        
        info = builder.get_sandbox_info(sandbox_id)
        assert info["isolation_mode"] == "directory"
        assert "container_id" not in info
        
        # Verify tools work
        builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="test.txt",
            content="Test"
        )
        
        # Cleanup
        builder.cleanup(sandbox_id)
