"""Unit tests for SandboxBuilder."""

import tempfile
from pathlib import Path
from unittest.mock import MagicMock, patch

import pytest

from src.sandbox_builder import SandboxBuilder
from src.skill_parser.skill_definition import SkillDefinition, Tool, ToolType


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
def sample_skill():
    """Create a sample skill definition for testing."""
    return SkillDefinition(
        name="Test Skill",
        description="A test skill",
        system_prompt="You are a test assistant.",
        tools=[
            Tool(name="read_file", tool_type=ToolType.FILESYSTEM, description="Read a file"),
            Tool(name="write_file", tool_type=ToolType.FILESYSTEM, description="Write a file"),
        ],
        environment_requirements={},
        metadata={}
    )


@pytest.fixture
def sample_skill_file(temp_dir):
    """Create a sample skill file for testing."""
    skill_file = Path(temp_dir) / "test_skill.md"
    skill_file.write_text("""# Test Skill

## Description
A test skill

## System Prompt
You are a test assistant.

## Tools
- read_file: Read a file
- write_file: Write a file
""")
    return str(skill_file)


class TestSandboxBuilderInit:
    """Test SandboxBuilder initialization."""
    
    def test_init_default_path(self):
        """Test initialization with default path."""
        builder = SandboxBuilder()
        assert builder.skill_parser is not None
        assert builder.sandbox_manager is not None
        assert builder.isolation_mode == "container"
    
    def test_init_custom_path(self, temp_dir):
        """Test initialization with custom path."""
        builder = SandboxBuilder(sandbox_base_path=temp_dir)
        assert builder.sandbox_manager.base_path == Path(temp_dir).resolve()
        assert builder.isolation_mode == "container"
    
    def test_init_with_isolation_mode(self, temp_dir):
        """Test initialization with isolation mode."""
        builder = SandboxBuilder(
            sandbox_base_path=temp_dir,
            isolation_mode="directory"
        )
        assert builder.isolation_mode == "directory"
        assert builder.sandbox_manager.isolation_mode == "directory"


class TestBuildFromSkillFile:
    """Test build_from_skill_file method."""
    
    def test_build_from_valid_skill_file(self, builder, sample_skill_file):
        """Test building sandbox from a valid skill file."""
        sandbox_id = builder.build_from_skill_file(sample_skill_file)
        
        assert sandbox_id is not None
        assert isinstance(sandbox_id, str)
        assert len(sandbox_id) > 0
        
        # Verify sandbox was created
        info = builder.get_sandbox_info(sandbox_id)
        assert info is not None
        assert info["skill_name"] == "Test Skill"
    
    def test_build_from_nonexistent_file(self, builder):
        """Test building sandbox from nonexistent file."""
        with pytest.raises(FileNotFoundError):
            builder.build_from_skill_file("nonexistent.md")
    
    def test_build_delegates_to_manager(self, builder, sample_skill_file):
        """Test that build_from_skill_file delegates to manager."""
        with patch.object(builder.sandbox_manager, 'create_sandbox') as mock_create:
            mock_create.return_value = "test-sandbox-id"
            
            result = builder.build_from_skill_file(sample_skill_file)
            
            assert result == "test-sandbox-id"
            mock_create.assert_called_once()
            # Verify it was called with a SkillDefinition
            call_args = mock_create.call_args[0][0]
            assert isinstance(call_args, SkillDefinition)


class TestBuildFromSkillDefinition:
    """Test build_from_skill_definition method."""
    
    def test_build_from_skill_definition(self, builder, sample_skill):
        """Test building sandbox from skill definition."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        assert sandbox_id is not None
        assert isinstance(sandbox_id, str)
        
        # Verify sandbox was created
        info = builder.get_sandbox_info(sandbox_id)
        assert info is not None
        assert info["skill_name"] == "Test Skill"
    
    def test_build_delegates_to_manager(self, builder, sample_skill):
        """Test that build_from_skill_definition delegates to manager."""
        with patch.object(builder.sandbox_manager, 'create_sandbox') as mock_create:
            mock_create.return_value = "test-sandbox-id"
            
            result = builder.build_from_skill_definition(sample_skill)
            
            assert result == "test-sandbox-id"
            # Should be called with skill and optional container_config
            mock_create.assert_called_once()
            assert mock_create.call_args[0][0] == sample_skill


class TestGetSandboxInfo:
    """Test get_sandbox_info method."""
    
    def test_get_sandbox_info_existing(self, builder, sample_skill):
        """Test getting info for existing sandbox."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        info = builder.get_sandbox_info(sandbox_id)
        
        assert info is not None
        assert info["sandbox_id"] == sandbox_id
        assert info["skill_name"] == "Test Skill"
        assert "tools" in info
        assert "workspace_path" in info
        assert "isolation_mode" in info
        assert info["isolation_mode"] == "container"
    
    def test_get_sandbox_info_nonexistent(self, builder):
        """Test getting info for nonexistent sandbox."""
        info = builder.get_sandbox_info("nonexistent-id")
        assert info is None
    
    def test_get_sandbox_info_delegates_to_manager(self, builder, sample_skill):
        """Test that get_sandbox_info delegates to manager."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        with patch.object(builder.sandbox_manager, 'get_sandbox') as mock_get:
            mock_get.return_value = {"test": "info"}
            
            result = builder.get_sandbox_info(sandbox_id)
            
            assert result == {"test": "info"}
            mock_get.assert_called_once_with(sandbox_id)


class TestExecuteInSandbox:
    """Test execute_in_sandbox method."""
    
    def test_execute_tool_in_sandbox(self, builder, sample_skill):
        """Test executing a tool in a sandbox."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        # Write a file
        result = builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="test.txt",
            content="Hello, world!"
        )
        
        assert result is not None
        assert "success" in result or "file_path" in result
        
        # Read the file back
        content = builder.execute_in_sandbox(
            sandbox_id,
            "read_file",
            file_path="test.txt"
        )
        
        assert "Hello, world!" in content
    
    def test_execute_nonexistent_tool(self, builder, sample_skill):
        """Test executing a nonexistent tool."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        with pytest.raises(ValueError, match="not available"):
            builder.execute_in_sandbox(
                sandbox_id,
                "nonexistent_tool",
                param="value"
            )
    
    def test_execute_in_nonexistent_sandbox(self, builder):
        """Test executing tool in nonexistent sandbox."""
        with pytest.raises(ValueError, match="not found"):
            builder.execute_in_sandbox(
                "nonexistent-id",
                "read_file",
                file_path="test.txt"
            )
    
    def test_execute_delegates_to_manager(self, builder, sample_skill):
        """Test that execute_in_sandbox delegates to manager."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        with patch.object(builder.sandbox_manager, 'execute_tool') as mock_execute:
            mock_execute.return_value = "test-result"
            
            result = builder.execute_in_sandbox(
                sandbox_id,
                "read_file",
                file_path="test.txt"
            )
            
            assert result == "test-result"
            mock_execute.assert_called_once_with(
                sandbox_id,
                "read_file",
                file_path="test.txt"
            )


class TestListTools:
    """Test list_tools method."""
    
    def test_list_tools(self, builder, sample_skill):
        """Test listing tools in a sandbox."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        tools = builder.list_tools(sandbox_id)
        
        assert isinstance(tools, list)
        assert "read_file" in tools
        assert "write_file" in tools
    
    def test_list_tools_nonexistent_sandbox(self, builder):
        """Test listing tools for nonexistent sandbox."""
        with pytest.raises(ValueError, match="not found"):
            builder.list_tools("nonexistent-id")
    
    def test_list_tools_delegates_to_manager(self, builder, sample_skill):
        """Test that list_tools delegates to manager."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        with patch.object(builder.sandbox_manager, 'list_tools') as mock_list:
            mock_list.return_value = ["tool1", "tool2"]
            
            result = builder.list_tools(sandbox_id)
            
            assert result == ["tool1", "tool2"]
            mock_list.assert_called_once_with(sandbox_id)


class TestCleanup:
    """Test cleanup methods."""
    
    def test_cleanup_sandbox(self, builder, sample_skill):
        """Test cleaning up a sandbox."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        # Verify sandbox exists
        assert builder.get_sandbox_info(sandbox_id) is not None
        
        # Cleanup
        result = builder.cleanup(sandbox_id)
        assert result is True
        
        # Verify sandbox is gone
        assert builder.get_sandbox_info(sandbox_id) is None
    
    def test_cleanup_nonexistent_sandbox(self, builder):
        """Test cleaning up nonexistent sandbox."""
        result = builder.cleanup("nonexistent-id")
        assert result is False
    
    def test_cleanup_all(self, builder, sample_skill):
        """Test cleaning up all sandboxes."""
        # Create multiple sandboxes
        sandbox_id1 = builder.build_from_skill_definition(sample_skill)
        sandbox_id2 = builder.build_from_skill_definition(sample_skill)
        
        # Verify they exist
        assert builder.get_sandbox_info(sandbox_id1) is not None
        assert builder.get_sandbox_info(sandbox_id2) is not None
        
        # Cleanup all
        count = builder.cleanup_all()
        assert count == 2
        
        # Verify they're gone
        assert builder.get_sandbox_info(sandbox_id1) is None
        assert builder.get_sandbox_info(sandbox_id2) is None
    
    def test_cleanup_delegates_to_manager(self, builder, sample_skill):
        """Test that cleanup delegates to manager."""
        sandbox_id = builder.build_from_skill_definition(sample_skill)
        
        with patch.object(builder.sandbox_manager, 'cleanup_sandbox') as mock_cleanup:
            mock_cleanup.return_value = True
            
            result = builder.cleanup(sandbox_id)
            
            assert result is True
            mock_cleanup.assert_called_once_with(sandbox_id)
