"""Tests for skill definition data structures."""

import pytest
from src.skill_parser.skill_definition import SkillDefinition, Tool, ToolType


class TestTool:
    """Tests for Tool dataclass."""
    
    def test_tool_creation(self):
        """Test creating a tool with all fields."""
        tool = Tool(
            name="read_file",
            tool_type=ToolType.FILESYSTEM,
            description="Read a file from the filesystem",
            parameters={"file_path": "str"},
            implementation="filesystem.read_file"
        )
        
        assert tool.name == "read_file"
        assert tool.tool_type == ToolType.FILESYSTEM
        assert tool.description == "Read a file from the filesystem"
        assert tool.parameters == {"file_path": "str"}
        assert tool.implementation == "filesystem.read_file"
    
    def test_tool_minimal(self):
        """Test creating a tool with minimal fields."""
        tool = Tool(
            name="web_search",
            tool_type=ToolType.WEB_SEARCH,
            description="Search the web"
        )
        
        assert tool.name == "web_search"
        assert tool.tool_type == ToolType.WEB_SEARCH
        assert tool.description == "Search the web"
        assert tool.parameters == {}
        assert tool.implementation is None
    
    def test_tool_empty_name_raises_error(self):
        """Test that empty tool name raises ValueError."""
        with pytest.raises(ValueError, match="Tool name cannot be empty"):
            Tool(
                name="",
                tool_type=ToolType.CUSTOM,
                description="Test"
            )
    
    def test_tool_empty_description_raises_error(self):
        """Test that empty tool description raises ValueError."""
        with pytest.raises(ValueError, match="Tool description cannot be empty"):
            Tool(
                name="test_tool",
                tool_type=ToolType.CUSTOM,
                description=""
            )


class TestSkillDefinition:
    """Tests for SkillDefinition dataclass."""
    
    def test_skill_creation(self):
        """Test creating a skill with all fields."""
        tools = [
            Tool(name="read_file", tool_type=ToolType.FILESYSTEM, description="Read file"),
            Tool(name="write_file", tool_type=ToolType.FILESYSTEM, description="Write file")
        ]
        
        skill = SkillDefinition(
            name="Test Skill",
            description="A test skill",
            system_prompt="You are a test assistant",
            tools=tools,
            environment_requirements={"python_version": "3.11"},
            metadata={"version": "1.0"}
        )
        
        assert skill.name == "Test Skill"
        assert skill.description == "A test skill"
        assert skill.system_prompt == "You are a test assistant"
        assert len(skill.tools) == 2
        assert skill.environment_requirements == {"python_version": "3.11"}
        assert skill.metadata == {"version": "1.0"}
    
    def test_skill_minimal(self):
        """Test creating a skill with minimal fields."""
        skill = SkillDefinition(
            name="Minimal Skill",
            description="A minimal skill",
            system_prompt="You are a minimal assistant"
        )
        
        assert skill.name == "Minimal Skill"
        assert skill.description == "A minimal skill"
        assert skill.system_prompt == "You are a minimal assistant"
        assert skill.tools == []
        assert skill.environment_requirements == {}
        assert skill.metadata == {}
    
    def test_skill_empty_name_raises_error(self):
        """Test that empty skill name raises ValueError."""
        with pytest.raises(ValueError, match="Skill name cannot be empty"):
            SkillDefinition(
                name="",
                description="Test",
                system_prompt="Test prompt"
            )
    
    def test_skill_empty_description_raises_error(self):
        """Test that empty description raises ValueError."""
        with pytest.raises(ValueError, match="Skill description cannot be empty"):
            SkillDefinition(
                name="Test",
                description="",
                system_prompt="Test prompt"
            )
    
    def test_skill_empty_system_prompt_raises_error(self):
        """Test that empty system prompt raises ValueError."""
        with pytest.raises(ValueError, match="System prompt cannot be empty"):
            SkillDefinition(
                name="Test",
                description="Test description",
                system_prompt=""
            )
    
    def test_get_tool_names(self):
        """Test getting list of tool names."""
        tools = [
            Tool(name="read_file", tool_type=ToolType.FILESYSTEM, description="Read"),
            Tool(name="write_file", tool_type=ToolType.FILESYSTEM, description="Write"),
            Tool(name="web_search", tool_type=ToolType.WEB_SEARCH, description="Search")
        ]
        
        skill = SkillDefinition(
            name="Test",
            description="Test",
            system_prompt="Test",
            tools=tools
        )
        
        tool_names = skill.get_tool_names()
        assert len(tool_names) == 3
        assert "read_file" in tool_names
        assert "write_file" in tool_names
        assert "web_search" in tool_names
    
    def test_get_tool_by_name_found(self):
        """Test getting a tool by name when it exists."""
        tools = [
            Tool(name="read_file", tool_type=ToolType.FILESYSTEM, description="Read"),
            Tool(name="write_file", tool_type=ToolType.FILESYSTEM, description="Write")
        ]
        
        skill = SkillDefinition(
            name="Test",
            description="Test",
            system_prompt="Test",
            tools=tools
        )
        
        tool = skill.get_tool_by_name("read_file")
        assert tool is not None
        assert tool.name == "read_file"
        assert tool.tool_type == ToolType.FILESYSTEM
    
    def test_get_tool_by_name_not_found(self):
        """Test getting a tool by name when it doesn't exist."""
        skill = SkillDefinition(
            name="Test",
            description="Test",
            system_prompt="Test",
            tools=[]
        )
        
        tool = skill.get_tool_by_name("nonexistent")
        assert tool is None


class TestToolType:
    """Tests for ToolType enum."""
    
    def test_tool_type_values(self):
        """Test that all expected tool types exist."""
        assert ToolType.FILESYSTEM.value == "filesystem"
        assert ToolType.WEB_SEARCH.value == "web_search"
        assert ToolType.CODEBASE_SEARCH.value == "codebase_search"
        assert ToolType.CODE_EXECUTION.value == "code_execution"
        assert ToolType.DATABASE.value == "database"
        assert ToolType.CUSTOM.value == "custom"
