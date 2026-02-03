"""Sandbox manager for managing sandbox lifecycle and tool execution."""

import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

from src.sandbox.environment import EnvironmentBuilder
from src.skill_parser.skill_definition import SkillDefinition
from src.tools.base import ToolBase
from src.tools.registry import ToolRegistry


class SandboxManager:
    """Manages sandbox lifecycle and tool execution.
    
    Creates sandboxes from skill definitions, tracks active sandboxes,
    and provides tool execution within isolated environments.
    """
    
    def __init__(self, base_path: str = "./sandboxes"):
        """Initialize the sandbox manager.
        
        Args:
            base_path: Base directory where sandboxes will be created
        """
        self.base_path = Path(base_path).resolve()
        self.environment_builder = EnvironmentBuilder(str(self.base_path))
        self.tool_registry = ToolRegistry()
        self.active_sandboxes: Dict[str, Dict[str, Any]] = {}
    
    def create_sandbox(self, skill: SkillDefinition) -> str:
        """Create a new sandbox from a skill definition.
        
        Args:
            skill: The skill definition to create a sandbox for
            
        Returns:
            Unique sandbox_id (UUID string)
            
        Raises:
            RuntimeError: If sandbox creation fails
        """
        # Generate unique sandbox ID
        sandbox_id = str(uuid.uuid4())
        
        try:
            # Create environment
            sandbox_path = self.environment_builder.create_environment(
                skill, 
                sandbox_id
            )
            
            workspace_path = sandbox_path / "workspace"
            
            # Initialize tools for this sandbox
            tools = {}
            for tool_name in skill.get_tool_names():
                tool_instance = self.tool_registry.get_tool(
                    tool_name,
                    base_path=str(workspace_path)
                )
                if tool_instance:
                    tools[tool_name] = tool_instance
                else:
                    # Tool not found in registry - skip it
                    # Could log a warning here in the future
                    pass
            
            # Store sandbox info
            sandbox_info = {
                "sandbox_id": sandbox_id,
                "skill": skill,
                "sandbox_path": sandbox_path,
                "workspace_path": workspace_path,
                "tools": tools,
                "status": "active",
            }
            
            self.active_sandboxes[sandbox_id] = sandbox_info
            
            return sandbox_id
            
        except Exception as e:
            raise RuntimeError(
                f"Failed to create sandbox for skill '{skill.name}': {e}"
            ) from e
    
    def get_sandbox(self, sandbox_id: str) -> Optional[Dict[str, Any]]:
        """Get information about a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox
            
        Returns:
            Dictionary with sandbox information, or None if not found
        """
        if sandbox_id not in self.active_sandboxes:
            return None
        
        sandbox_info = self.active_sandboxes[sandbox_id].copy()
        
        # Don't expose the full skill object, just key info
        skill = sandbox_info.pop("skill")
        return {
            "sandbox_id": sandbox_info["sandbox_id"],
            "skill_name": skill.name,
            "skill_description": skill.description,
            "sandbox_path": str(sandbox_info["sandbox_path"]),
            "workspace_path": str(sandbox_info["workspace_path"]),
            "tools": list(sandbox_info["tools"].keys()),
            "status": sandbox_info["status"],
        }
    
    def execute_tool(
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
        """
        if sandbox_id not in self.active_sandboxes:
            raise ValueError(f"Sandbox {sandbox_id} not found")
        
        sandbox_info = self.active_sandboxes[sandbox_id]
        
        if sandbox_info["status"] != "active":
            raise ValueError(
                f"Sandbox {sandbox_id} is not active (status: {sandbox_info['status']})"
            )
        
        if tool_name not in sandbox_info["tools"]:
            raise ValueError(
                f"Tool '{tool_name}' not available in sandbox {sandbox_id}. "
                f"Available tools: {list(sandbox_info['tools'].keys())}"
            )
        
        tool = sandbox_info["tools"][tool_name]
        
        try:
            return tool.execute(**kwargs)
        except Exception as e:
            raise RuntimeError(
                f"Tool execution failed for '{tool_name}' in sandbox {sandbox_id}: {e}"
            ) from e
    
    def list_tools(self, sandbox_id: str) -> List[str]:
        """List available tools in a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox
            
        Returns:
            List of tool names available in the sandbox
            
        Raises:
            ValueError: If sandbox doesn't exist
        """
        if sandbox_id not in self.active_sandboxes:
            raise ValueError(f"Sandbox {sandbox_id} not found")
        
        return list(self.active_sandboxes[sandbox_id]["tools"].keys())
    
    def cleanup_sandbox(self, sandbox_id: str) -> bool:
        """Clean up a sandbox.
        
        Args:
            sandbox_id: Unique identifier for the sandbox to clean up
            
        Returns:
            True if sandbox was cleaned up, False if it didn't exist
        """
        if sandbox_id not in self.active_sandboxes:
            return False
        
        try:
            # Remove from active sandboxes
            sandbox_info = self.active_sandboxes.pop(sandbox_id)
            
            # Clean up environment
            self.environment_builder.cleanup(sandbox_id)
            
            return True
            
        except Exception as e:
            # Re-add to active sandboxes if cleanup failed
            if sandbox_id not in self.active_sandboxes:
                self.active_sandboxes[sandbox_id] = sandbox_info
            raise RuntimeError(
                f"Failed to cleanup sandbox {sandbox_id}: {e}"
            ) from e
    
    def cleanup_all(self) -> int:
        """Clean up all active sandboxes.
        
        Returns:
            Number of sandboxes cleaned up
        """
        sandbox_ids = list(self.active_sandboxes.keys())
        cleaned_count = 0
        
        for sandbox_id in sandbox_ids:
            try:
                if self.cleanup_sandbox(sandbox_id):
                    cleaned_count += 1
            except Exception:
                # Continue cleaning up other sandboxes even if one fails
                pass
        
        return cleaned_count
