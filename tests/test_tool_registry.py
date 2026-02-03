"""Tests for tool registry."""

from pathlib import Path

import pytest

from src.tools.base import ToolBase
from src.tools.implementations.filesystem import (
    ListFilesTool,
    ReadFileTool,
    WriteFileTool,
)
from src.tools.registry import ToolRegistry


class CustomTool(ToolBase):
    """Custom tool for testing."""
    
    def __init__(self, name: str = "custom_tool", description: str = "A custom tool"):
        super().__init__(name=name, description=description)
    
    def execute(self, **kwargs):
        return {"custom": True}
    
    def validate_parameters(self, **kwargs):
        return True


class TestToolRegistry:
    """Test cases for ToolRegistry."""
    
    def test_initialization_registers_default_tools(self):
        """Test that default tools are registered on initialization."""
        registry = ToolRegistry()
        
        assert registry.has_tool("read_file")
        assert registry.has_tool("write_file")
        assert registry.has_tool("list_files")
    
    def test_list_tools_includes_defaults(self):
        """Test that list_tools includes default tools."""
        registry = ToolRegistry()
        tools = registry.list_tools()
        
        assert "read_file" in tools
        assert "write_file" in tools
        assert "list_files" in tools
    
    def test_register_tool(self):
        """Test registering a custom tool."""
        registry = ToolRegistry()
        registry.register("custom_tool", CustomTool)
        
        assert registry.has_tool("custom_tool")
        assert "custom_tool" in registry.list_tools()
    
    def test_register_empty_name_raises_error(self):
        """Test that registering with empty name raises ValueError."""
        registry = ToolRegistry()
        with pytest.raises(ValueError, match="name cannot be empty"):
            registry.register("", CustomTool)
    
    def test_register_invalid_class_raises_error(self):
        """Test that registering non-ToolBase class raises ValueError."""
        registry = ToolRegistry()
        
        class NotATool:
            pass
        
        with pytest.raises(ValueError, match="must inherit from ToolBase"):
            registry.register("invalid", NotATool)
    
    def test_get_tool_default_tools(self):
        """Test getting instances of default tools."""
        registry = ToolRegistry()
        
        read_tool = registry.get_tool("read_file", base_path="/test")
        assert isinstance(read_tool, ReadFileTool)
        assert read_tool.base_path == Path("/test").resolve()
        
        write_tool = registry.get_tool("write_file", base_path="/test")
        assert isinstance(write_tool, WriteFileTool)
        
        list_tool = registry.get_tool("list_files", base_path="/test")
        assert isinstance(list_tool, ListFilesTool)
    
    def test_get_tool_custom_tool(self):
        """Test getting instance of custom tool."""
        registry = ToolRegistry()
        registry.register("custom", CustomTool)
        
        tool = registry.get_tool("custom")
        assert isinstance(tool, CustomTool)
    
    def test_get_tool_nonexistent_returns_none(self):
        """Test that getting non-existent tool returns None."""
        registry = ToolRegistry()
        assert registry.get_tool("nonexistent") is None
    
    def test_get_tool_with_kwargs(self):
        """Test that get_tool passes kwargs to tool constructor."""
        registry = ToolRegistry()
        
        tool = registry.get_tool("read_file", base_path="/custom/path")
        assert tool.base_path == Path("/custom/path").resolve()
    
    def test_has_tool(self):
        """Test has_tool method."""
        registry = ToolRegistry()
        
        assert registry.has_tool("read_file") is True
        assert registry.has_tool("nonexistent") is False
    
    def test_unregister_tool(self):
        """Test unregistering a tool."""
        registry = ToolRegistry()
        
        # Register a custom tool
        registry.register("custom", CustomTool)
        assert registry.has_tool("custom") is True
        
        # Unregister it
        result = registry.unregister("custom")
        assert result is True
        assert registry.has_tool("custom") is False
    
    def test_unregister_nonexistent_tool(self):
        """Test unregistering a non-existent tool returns False."""
        registry = ToolRegistry()
        result = registry.unregister("nonexistent")
        assert result is False
    
    def test_unregister_default_tool(self):
        """Test unregistering a default tool."""
        registry = ToolRegistry()
        
        assert registry.has_tool("read_file") is True
        result = registry.unregister("read_file")
        assert result is True
        assert registry.has_tool("read_file") is False
    
    def test_multiple_registries_independent(self):
        """Test that multiple registries are independent."""
        registry1 = ToolRegistry()
        registry2 = ToolRegistry()
        
        registry1.register("custom1", CustomTool)
        registry2.register("custom2", CustomTool)
        
        assert registry1.has_tool("custom1") is True
        assert registry1.has_tool("custom2") is False
        
        assert registry2.has_tool("custom1") is False
        assert registry2.has_tool("custom2") is True
