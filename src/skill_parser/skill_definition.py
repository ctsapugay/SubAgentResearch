"""Data structures for representing skill/subagent definitions."""

from dataclasses import dataclass, field
from enum import Enum
from typing import Any, Dict, List, Optional


class ToolType(Enum):
    """Enumeration of tool types that can be used by skills."""
    FILESYSTEM = "filesystem"
    WEB_SEARCH = "web_search"
    CODEBASE_SEARCH = "codebase_search"
    CODE_EXECUTION = "code_execution"
    DATABASE = "database"
    CUSTOM = "custom"


@dataclass
class Tool:
    """Represents a tool available to a skill/subagent."""
    name: str
    tool_type: ToolType
    description: str
    parameters: Dict[str, Any] = field(default_factory=dict)
    implementation: Optional[str] = None
    
    def __post_init__(self):
        """Validate tool after initialization."""
        if not self.name:
            raise ValueError("Tool name cannot be empty")
        if not self.description:
            raise ValueError("Tool description cannot be empty")


@dataclass
class SkillDefinition:
    """Represents a complete skill/subagent definition."""
    name: str
    description: str
    system_prompt: str
    tools: List[Tool] = field(default_factory=list)
    environment_requirements: Dict[str, Any] = field(default_factory=dict)
    metadata: Dict[str, Any] = field(default_factory=dict)
    
    def __post_init__(self):
        """Validate skill definition after initialization."""
        if not self.name:
            raise ValueError("Skill name cannot be empty")
        if not self.description:
            raise ValueError("Skill description cannot be empty")
        if not self.system_prompt:
            raise ValueError("System prompt cannot be empty")
    
    def get_tool_names(self) -> List[str]:
        """Return a list of all tool names."""
        return [tool.name for tool in self.tools]
    
    def get_tool_by_name(self, name: str) -> Optional[Tool]:
        """Get a tool by its name, or None if not found."""
        for tool in self.tools:
            if tool.name == name:
                return tool
        return None
