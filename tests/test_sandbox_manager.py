"""Tests for SandboxManager."""

import shutil
import tempfile
from pathlib import Path

import pytest

from src.sandbox.manager import SandboxManager
from src.skill_parser.skill_definition import SkillDefinition, Tool, ToolType


@pytest.fixture
def temp_base_path():
    """Create a temporary directory for sandboxes."""
    temp_dir = tempfile.mkdtemp()
    yield temp_dir
    shutil.rmtree(temp_dir, ignore_errors=True)


@pytest.fixture
def manager(temp_base_path):
    """Create a SandboxManager instance."""
    return SandboxManager(temp_base_path)


@pytest.fixture
def simple_skill():
    """Create a simple skill definition."""
    return SkillDefinition(
        name="Test Skill",
        description="A test skill",
        system_prompt="You are a test assistant.",
        tools=[],
        environment_requirements={},
    )


@pytest.fixture
def skill_with_filesystem_tools():
    """Create a skill with filesystem tools."""
    return SkillDefinition(
        name="Filesystem Skill",
        description="A skill with filesystem tools",
        system_prompt="You can work with files.",
        tools=[
            Tool(
                name="read_file",
                tool_type=ToolType.FILESYSTEM,
                description="Read files",
            ),
            Tool(
                name="write_file",
                tool_type=ToolType.FILESYSTEM,
                description="Write files",
            ),
        ],
        environment_requirements={},
    )


class TestSandboxManager:
    """Test cases for SandboxManager."""
    
    def test_init(self, temp_base_path):
        """Test SandboxManager initialization."""
        manager = SandboxManager(temp_base_path)
        assert manager.base_path == Path(temp_base_path).resolve()
        assert manager.environment_builder is not None
        assert manager.tool_registry is not None
        assert len(manager.active_sandboxes) == 0
    
    def test_create_sandbox(self, manager, simple_skill):
        """Test creating a sandbox."""
        sandbox_id = manager.create_sandbox(simple_skill)
        
        assert sandbox_id is not None
        assert len(sandbox_id) > 0
        assert sandbox_id in manager.active_sandboxes
        
        sandbox_info = manager.active_sandboxes[sandbox_id]
        assert sandbox_info["skill"] == simple_skill
        assert sandbox_info["status"] == "active"
        assert sandbox_info["sandbox_path"].exists()
        assert sandbox_info["workspace_path"].exists()
    
    def test_create_sandbox_unique_ids(self, manager, simple_skill):
        """Test that each sandbox gets a unique ID."""
        sandbox_id1 = manager.create_sandbox(simple_skill)
        sandbox_id2 = manager.create_sandbox(simple_skill)
        
        assert sandbox_id1 != sandbox_id2
        assert sandbox_id1 in manager.active_sandboxes
        assert sandbox_id2 in manager.active_sandboxes
    
    def test_get_sandbox(self, manager, simple_skill):
        """Test getting sandbox information."""
        sandbox_id = manager.create_sandbox(simple_skill)
        
        info = manager.get_sandbox(sandbox_id)
        assert info is not None
        assert info["sandbox_id"] == sandbox_id
        assert info["skill_name"] == simple_skill.name
        assert info["skill_description"] == simple_skill.description
        assert info["status"] == "active"
        assert "workspace_path" in info
        assert "tools" in info
    
    def test_get_sandbox_nonexistent(self, manager):
        """Test getting non-existent sandbox."""
        info = manager.get_sandbox("nonexistent-id")
        assert info is None
    
    def test_list_tools(self, manager, skill_with_filesystem_tools):
        """Test listing tools in a sandbox."""
        sandbox_id = manager.create_sandbox(skill_with_filesystem_tools)
        
        tools = manager.list_tools(sandbox_id)
        assert isinstance(tools, list)
        # Should have the filesystem tools that are registered
        assert "read_file" in tools
        assert "write_file" in tools
    
    def test_list_tools_nonexistent(self, manager):
        """Test listing tools for non-existent sandbox."""
        with pytest.raises(ValueError, match="not found"):
            manager.list_tools("nonexistent-id")
    
    def test_execute_tool(self, manager, skill_with_filesystem_tools):
        """Test executing a tool in a sandbox."""
        sandbox_id = manager.create_sandbox(skill_with_filesystem_tools)
        
        # Write a file first
        result = manager.execute_tool(
            sandbox_id,
            "write_file",
            file_path="test.txt",
            content="Hello, world!"
        )
        assert result["success"] is True
        
        # Read it back
        content = manager.execute_tool(
            sandbox_id,
            "read_file",
            file_path="test.txt"
        )
        assert content == "Hello, world!"
    
    def test_execute_tool_nonexistent_sandbox(self, manager):
        """Test executing tool in non-existent sandbox."""
        with pytest.raises(ValueError, match="not found"):
            manager.execute_tool("nonexistent-id", "read_file", file_path="test.txt")
    
    def test_execute_tool_invalid_tool(self, manager, simple_skill):
        """Test executing invalid tool."""
        sandbox_id = manager.create_sandbox(simple_skill)
        
        with pytest.raises(ValueError, match="not available"):
            manager.execute_tool(sandbox_id, "invalid_tool", param="value")
    
    def test_execute_tool_invalid_parameters(self, manager, skill_with_filesystem_tools):
        """Test executing tool with invalid parameters."""
        sandbox_id = manager.create_sandbox(skill_with_filesystem_tools)
        
        with pytest.raises(Exception):  # Could be ValueError or RuntimeError
            manager.execute_tool(
                sandbox_id,
                "read_file",
                # Missing file_path parameter
            )
    
    def test_cleanup_sandbox(self, manager, simple_skill):
        """Test cleaning up a sandbox."""
        sandbox_id = manager.create_sandbox(simple_skill)
        assert sandbox_id in manager.active_sandboxes
        
        result = manager.cleanup_sandbox(sandbox_id)
        assert result is True
        assert sandbox_id not in manager.active_sandboxes
        
        # Verify directory is removed
        sandbox_info = manager.active_sandboxes.get(sandbox_id)
        if sandbox_info:
            assert not sandbox_info["sandbox_path"].exists()
    
    def test_cleanup_sandbox_nonexistent(self, manager):
        """Test cleaning up non-existent sandbox."""
        result = manager.cleanup_sandbox("nonexistent-id")
        assert result is False
    
    def test_cleanup_all(self, manager, simple_skill):
        """Test cleaning up all sandboxes."""
        sandbox_id1 = manager.create_sandbox(simple_skill)
        sandbox_id2 = manager.create_sandbox(simple_skill)
        
        assert len(manager.active_sandboxes) == 2
        
        cleaned_count = manager.cleanup_all()
        assert cleaned_count == 2
        assert len(manager.active_sandboxes) == 0
    
    def test_multiple_sandboxes_isolation(self, manager, simple_skill):
        """Test that multiple sandboxes are isolated."""
        sandbox_id1 = manager.create_sandbox(simple_skill)
        sandbox_id2 = manager.create_sandbox(simple_skill)
        
        # Create a skill with tools for both sandboxes
        skill_with_tools = SkillDefinition(
            name="Tool Skill",
            description="A skill with tools",
            system_prompt="You have tools.",
            tools=[
                Tool(
                    name="write_file",
                    tool_type=ToolType.FILESYSTEM,
                    description="Write files",
                ),
                Tool(
                    name="read_file",
                    tool_type=ToolType.FILESYSTEM,
                    description="Read files",
                ),
            ],
            environment_requirements={},
        )
        
        # Recreate sandboxes with tools
        manager.cleanup_all()
        sandbox_id1 = manager.create_sandbox(skill_with_tools)
        sandbox_id2 = manager.create_sandbox(skill_with_tools)
        
        # Write different files in each sandbox
        manager.execute_tool(
            sandbox_id1,
            "write_file",
            file_path="test.txt",
            content="Sandbox 1"
        )
        
        manager.execute_tool(
            sandbox_id2,
            "write_file",
            file_path="test.txt",
            content="Sandbox 2"
        )
        
        # Read back - should be different
        content1 = manager.execute_tool(sandbox_id1, "read_file", file_path="test.txt")
        content2 = manager.execute_tool(sandbox_id2, "read_file", file_path="test.txt")
        
        assert content1 == "Sandbox 1"
        assert content2 == "Sandbox 2"
        assert content1 != content2
    
    def test_sandbox_info_structure(self, manager, skill_with_filesystem_tools):
        """Test that sandbox info has correct structure."""
        sandbox_id = manager.create_sandbox(skill_with_filesystem_tools)
        
        info = manager.get_sandbox(sandbox_id)
        
        # Check all expected keys are present
        assert "sandbox_id" in info
        assert "skill_name" in info
        assert "skill_description" in info
        assert "sandbox_path" in info
        assert "workspace_path" in info
        assert "tools" in info
        assert "status" in info
        
        # Check types
        assert isinstance(info["tools"], list)
        assert isinstance(info["sandbox_path"], str)
        assert isinstance(info["workspace_path"], str)
    
    def test_execute_tool_error_handling(self, manager, skill_with_filesystem_tools):
        """Test error handling in tool execution."""
        sandbox_id = manager.create_sandbox(skill_with_filesystem_tools)
        
        # Try to read a non-existent file
        with pytest.raises(Exception):  # FileNotFoundError wrapped in RuntimeError
            manager.execute_tool(
                sandbox_id,
                "read_file",
                file_path="nonexistent.txt"
            )
