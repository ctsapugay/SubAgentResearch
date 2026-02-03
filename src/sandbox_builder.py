"""Main public interface for building sandboxes from skill definitions."""

from pathlib import Path
from typing import Any, Dict, Optional

from src.sandbox.manager import SandboxManager
from src.skill_parser.parser import SkillParser
from src.skill_parser.skill_definition import SkillDefinition


class SandboxBuilder:
    """Main public interface for creating and managing sandboxes from skills.
    
    This class provides a simple, clean API for:
    - Parsing skill files
    - Creating sandboxes from skill definitions
    - Executing tools within sandboxes
    - Managing sandbox lifecycle
    """
    
    def __init__(self, sandbox_base_path: str = "./sandboxes"):
        """Initialize the sandbox builder.
        
        Args:
            sandbox_base_path: Base directory where sandboxes will be created
        """
        self.skill_parser = SkillParser()
        self.sandbox_manager = SandboxManager(sandbox_base_path)
    
    def build_from_skill_file(self, skill_path: str) -> str:
        """Build a sandbox from a skill file path.
        
        Args:
            skill_path: Path to the SKILL.md file
            
        Returns:
            Unique sandbox_id (UUID string)
            
        Raises:
            FileNotFoundError: If the skill file doesn't exist
            ValueError: If the skill file cannot be parsed
            RuntimeError: If sandbox creation fails
        """
        # Parse the skill file
        skill = self.skill_parser.parse(skill_path)
        
        # Create sandbox from parsed skill
        return self.build_from_skill_definition(skill)
    
    def build_from_skill_definition(self, skill: SkillDefinition) -> str:
        """Build a sandbox from an already-parsed skill definition.
        
        Args:
            skill: The SkillDefinition object
            
        Returns:
            Unique sandbox_id (UUID string)
            
        Raises:
            RuntimeError: If sandbox creation fails
        """
        return self.sandbox_manager.create_sandbox(skill)
    
    def get_sandbox_info(self, sandbox_id: str) -> Optional[Dict[str, Any]]:
        """Get information about a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox
            
        Returns:
            Dictionary with sandbox information, or None if not found
            
        The returned dictionary contains:
            - sandbox_id: Unique identifier
            - skill_name: Name of the skill
            - skill_description: Description of the skill
            - sandbox_path: Path to the sandbox directory
            - workspace_path: Path to the workspace directory
            - tools: List of available tool names
            - status: Current status of the sandbox
        """
        return self.sandbox_manager.get_sandbox(sandbox_id)
    
    def execute_in_sandbox(
        self, 
        sandbox_id: str, 
        tool_name: str, 
        **kwargs
    ) -> Any:
        """Execute a tool within a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox
            tool_name: Name of the tool to execute
            **kwargs: Arguments to pass to the tool
            
        Returns:
            Result from tool execution
            
        Raises:
            ValueError: If sandbox or tool doesn't exist
            RuntimeError: If tool execution fails
            
        Example:
            >>> builder = SandboxBuilder()
            >>> sandbox_id = builder.build_from_skill_file("skill.md")
            >>> result = builder.execute_in_sandbox(
            ...     sandbox_id, 
            ...     "write_file",
            ...     file_path="test.txt",
            ...     content="Hello, world!"
            ... )
        """
        return self.sandbox_manager.execute_tool(sandbox_id, tool_name, **kwargs)
    
    def list_tools(self, sandbox_id: str) -> list:
        """List available tools in a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox
            
        Returns:
            List of tool names available in the sandbox
            
        Raises:
            ValueError: If sandbox doesn't exist
        """
        return self.sandbox_manager.list_tools(sandbox_id)
    
    def cleanup(self, sandbox_id: str) -> bool:
        """Clean up a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox to clean up
            
        Returns:
            True if sandbox was cleaned up, False if it didn't exist
        """
        return self.sandbox_manager.cleanup_sandbox(sandbox_id)
    
    def cleanup_all(self) -> int:
        """Clean up all active sandboxes.
        
        Returns:
            Number of sandboxes cleaned up
        """
        return self.sandbox_manager.cleanup_all()
