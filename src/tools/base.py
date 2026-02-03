"""Base tool interface for all tools in the sandbox system."""

from abc import ABC, abstractmethod
from typing import Any, Dict


class ToolBase(ABC):
    """Abstract base class for all tools.
    
    All tools must inherit from this class and implement the required
    abstract methods. Tools are executed within sandbox environments
    and must validate their parameters before execution.
    """
    
    def __init__(self, name: str, description: str):
        """Initialize a tool.
        
        Args:
            name: Unique name identifier for the tool
            description: Human-readable description of what the tool does
        """
        if not name:
            raise ValueError("Tool name cannot be empty")
        if not description:
            raise ValueError("Tool description cannot be empty")
        
        self._name = name
        self._description = description
    
    @property
    def name(self) -> str:
        """Get the tool's name."""
        return self._name
    
    @property
    def description(self) -> str:
        """Get the tool's description."""
        return self._description
    
    @abstractmethod
    def execute(self, **kwargs) -> Any:
        """Execute the tool with the given parameters.
        
        Args:
            **kwargs: Tool-specific parameters
            
        Returns:
            Tool-specific result (dict, list, str, etc.)
            
        Raises:
            ValueError: If parameters are invalid
            RuntimeError: If execution fails
        """
        pass
    
    @abstractmethod
    def validate_parameters(self, **kwargs) -> bool:
        """Validate that the provided parameters are correct.
        
        Args:
            **kwargs: Parameters to validate
            
        Returns:
            True if parameters are valid, False otherwise
            
        Note:
            This method should check parameter types, required fields,
            and any constraints before execution.
        """
        pass
    
    def get_schema(self) -> Dict[str, Any]:
        """Get JSON schema for this tool.
        
        Returns:
            Dictionary containing tool schema information including:
            - name: Tool name
            - description: Tool description
            - parameters: Parameter schema (if available)
        """
        return {
            "name": self.name,
            "description": self.description,
            "parameters": {}  # Subclasses can override to provide detailed schema
        }
    
    def __repr__(self) -> str:
        """String representation of the tool."""
        return f"{self.__class__.__name__}(name='{self.name}')"
