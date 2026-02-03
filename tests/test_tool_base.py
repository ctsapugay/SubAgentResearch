"""Tests for the base tool interface."""

import pytest

from src.tools.base import ToolBase


class ConcreteTool(ToolBase):
    """Concrete implementation of ToolBase for testing."""
    
    def execute(self, **kwargs):
        """Execute the tool."""
        return {"result": "success"}
    
    def validate_parameters(self, **kwargs):
        """Validate parameters."""
        return "test_param" in kwargs


class TestToolBase:
    """Test cases for ToolBase abstract class."""
    
    def test_cannot_instantiate_abstract_class(self):
        """Test that ToolBase cannot be instantiated directly."""
        with pytest.raises(TypeError):
            ToolBase(name="test", description="test")
    
    def test_concrete_tool_instantiation(self):
        """Test that a concrete tool can be instantiated."""
        tool = ConcreteTool(name="test_tool", description="A test tool")
        assert tool.name == "test_tool"
        assert tool.description == "A test tool"
    
    def test_tool_name_property(self):
        """Test that tool name property works correctly."""
        tool = ConcreteTool(name="my_tool", description="Description")
        assert tool.name == "my_tool"
    
    def test_tool_description_property(self):
        """Test that tool description property works correctly."""
        tool = ConcreteTool(name="my_tool", description="My description")
        assert tool.description == "My description"
    
    def test_empty_name_raises_error(self):
        """Test that empty name raises ValueError."""
        with pytest.raises(ValueError, match="name cannot be empty"):
            ConcreteTool(name="", description="Description")
    
    def test_empty_description_raises_error(self):
        """Test that empty description raises ValueError."""
        with pytest.raises(ValueError, match="description cannot be empty"):
            ConcreteTool(name="test", description="")
    
    def test_get_schema(self):
        """Test that get_schema returns proper structure."""
        tool = ConcreteTool(name="test_tool", description="Test description")
        schema = tool.get_schema()
        
        assert isinstance(schema, dict)
        assert schema["name"] == "test_tool"
        assert schema["description"] == "Test description"
        assert "parameters" in schema
    
    def test_repr(self):
        """Test string representation of tool."""
        tool = ConcreteTool(name="test_tool", description="Description")
        repr_str = repr(tool)
        assert "ConcreteTool" in repr_str
        assert "test_tool" in repr_str
    
    def test_execute_method(self):
        """Test that execute method works in concrete implementation."""
        tool = ConcreteTool(name="test", description="test")
        result = tool.execute(test_param="value")
        assert result == {"result": "success"}
    
    def test_validate_parameters_method(self):
        """Test that validate_parameters method works in concrete implementation."""
        tool = ConcreteTool(name="test", description="test")
        assert tool.validate_parameters(test_param="value") is True
        assert tool.validate_parameters(other_param="value") is False
