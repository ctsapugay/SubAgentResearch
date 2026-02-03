"""Tool registry for managing and instantiating tools."""

from typing import Dict, List, Optional, Type

from src.tools.base import ToolBase
from src.tools.implementations.filesystem import (
    ListFilesTool,
    ReadFileTool,
    WriteFileTool,
)


class ToolRegistry:
    """Registry for managing tool classes and creating tool instances.
    
    The registry maintains a catalog of available tools and provides
    methods to register new tools and instantiate them with specific
    configuration (like base_path for sandbox isolation).
    """
    
    def __init__(self):
        """Initialize the tool registry with default tools."""
        self._tools: Dict[str, Type[ToolBase]] = {}
        self._register_default_tools()
    
    def _register_default_tools(self) -> None:
        """Register default filesystem tools."""
        self.register("read_file", ReadFileTool)
        self.register("write_file", WriteFileTool)
        self.register("list_files", ListFilesTool)
    
    def register(self, name: str, tool_class: Type[ToolBase]) -> None:
        """Register a tool class.
        
        Args:
            name: Unique name identifier for the tool
            tool_class: Tool class (must inherit from ToolBase)
            
        Raises:
            ValueError: If name is empty or tool_class is invalid
        """
        if not name:
            raise ValueError("Tool name cannot be empty")
        
        if not issubclass(tool_class, ToolBase):
            raise ValueError(
                f"Tool class {tool_class} must inherit from ToolBase"
            )
        
        self._tools[name] = tool_class
    
    def get_tool(self, name: str, **init_kwargs) -> Optional[ToolBase]:
        """Get an instance of a tool.
        
        Args:
            name: Name of the tool to retrieve
            **init_kwargs: Keyword arguments to pass to tool constructor
                          (e.g., base_path for filesystem tools)
            
        Returns:
            Tool instance if found, None otherwise
        """
        if name not in self._tools:
            return None
        
        tool_class = self._tools[name]
        return tool_class(**init_kwargs)
    
    def has_tool(self, name: str) -> bool:
        """Check if a tool is registered.
        
        Args:
            name: Name of the tool to check
            
        Returns:
            True if tool is registered, False otherwise
        """
        return name in self._tools
    
    def list_tools(self) -> List[str]:
        """List all registered tool names.
        
        Returns:
            List of registered tool names
        """
        return list(self._tools.keys())
    
    def unregister(self, name: str) -> bool:
        """Unregister a tool.
        
        Args:
            name: Name of the tool to unregister
            
        Returns:
            True if tool was unregistered, False if it wasn't registered
        """
        if name in self._tools:
            del self._tools[name]
            return True
        return False
