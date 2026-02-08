"""Sandbox manager for managing sandbox lifecycle and tool execution."""

import logging
import uuid
from pathlib import Path
from typing import Any, Dict, List, Optional

from src.sandbox.container_config import ContainerConfig
from src.sandbox.container_environment import ContainerEnvironmentBuilder
from src.sandbox.container_executor import ContainerToolExecutor
from src.sandbox.environment import EnvironmentBuilder
from src.skill_parser.skill_definition import SkillDefinition
from src.tools.base import ToolBase
from src.tools.registry import ToolRegistry

logger = logging.getLogger(__name__)


class SandboxManager:
    """Manages sandbox lifecycle and tool execution.
    
    Creates sandboxes from skill definitions, tracks active sandboxes,
    and provides tool execution within isolated environments.
    
    Supports two isolation modes:
    - "container": Docker container-based isolation with stronger security (default)
    - "directory": Directory-based isolation with virtual environments
    """
    
    def __init__(
        self,
        base_path: str = "./sandboxes",
        isolation_mode: str = "container",
        container_config: Optional[ContainerConfig] = None
    ):
        """Initialize the sandbox manager.
        
        Args:
            base_path: Base directory where sandboxes will be created
            isolation_mode: Isolation method ("container" or "directory", defaults to "container")
            container_config: Configuration for container mode (optional, uses defaults if not provided)
        
        Raises:
            ValueError: If isolation_mode is invalid or container_config is missing for container mode
            RuntimeError: If Docker is required but not available
        """
        if isolation_mode not in ("directory", "container"):
            raise ValueError(
                f"isolation_mode must be 'directory' or 'container', got '{isolation_mode}'"
            )
        
        self.base_path = Path(base_path).resolve()
        self.isolation_mode = isolation_mode
        self.environment_builder = EnvironmentBuilder(str(self.base_path))
        self.tool_registry = ToolRegistry()
        self.active_sandboxes: Dict[str, Dict[str, Any]] = {}
        
        # Initialize container components if container mode is enabled
        self.container_environment_builder: Optional[ContainerEnvironmentBuilder] = None
        self.container_executor: Optional[ContainerToolExecutor] = None
        
        if isolation_mode == "container":
            try:
                import docker
                docker_client = docker.from_env()
            except ImportError:
                raise RuntimeError(
                    "Docker SDK not available. Install with: pip install docker>=6.0.0"
                )
            except Exception as e:
                raise RuntimeError(
                    f"Failed to connect to Docker daemon: {e}. "
                    "Make sure Docker is running."
                ) from e
            
            if container_config is None:
                container_config = ContainerConfig()
            
            self.container_environment_builder = ContainerEnvironmentBuilder(
                docker_client=docker_client,
                base_path=str(self.base_path)
            )
            
            # Create ContainerManager instance for the executor
            from src.sandbox.container import ContainerManager
            container_manager = ContainerManager(
                docker_client=docker_client,
                base_path=str(self.base_path)
            )
            self.container_executor = ContainerToolExecutor(container_manager)
            
            logger.info(f"SandboxManager initialized with container isolation mode")
        else:
            logger.info(f"SandboxManager initialized with directory isolation mode")
    
    def create_sandbox(
        self,
        skill: SkillDefinition,
        container_config: Optional[ContainerConfig] = None
    ) -> str:
        """Create a new sandbox from a skill definition.
        
        Args:
            skill: The skill definition to create a sandbox for
            container_config: Optional container configuration (overrides default if provided)
            
        Returns:
            Unique sandbox_id (UUID string)
            
        Raises:
            RuntimeError: If sandbox creation fails
        """
        # Generate unique sandbox ID
        sandbox_id = str(uuid.uuid4())
        
        try:
            container_id: Optional[str] = None
            
            if self.isolation_mode == "container":
                # Use container-based environment
                if container_config is None:
                    # Use default config from __init__ or create new default
                    container_config = ContainerConfig()
                
                if self.container_environment_builder is None:
                    raise RuntimeError(
                        "Container environment builder not initialized. "
                        "This should not happen if isolation_mode='container'."
                    )
                
                env_info = self.container_environment_builder.create_environment(
                    skill, sandbox_id, container_config
                )
                container_id = env_info["container_id"]
                workspace_path = Path(env_info["workspace_path"])
                sandbox_path = workspace_path.parent
                
                # For container mode, tools are executed via container executor
                # Store tool names but not instances
                tools = {tool_name: None for tool_name in skill.get_tool_names()}
                
                # Always include default registered tools so sandboxes have
                # base tools even when skills don't explicitly declare them
                for default_tool_name in self.tool_registry.list_tools():
                    if default_tool_name not in tools:
                        tools[default_tool_name] = None
            else:
                # Use directory-based environment (existing code)
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
                
                # Always include default registered tools so sandboxes have
                # base tools even when skills don't explicitly declare them
                for default_tool_name in self.tool_registry.list_tools():
                    if default_tool_name not in tools:
                        tool_instance = self.tool_registry.get_tool(
                            default_tool_name,
                            base_path=str(workspace_path)
                        )
                        if tool_instance:
                            tools[default_tool_name] = tool_instance
            
            # Store sandbox info
            sandbox_info = {
                "sandbox_id": sandbox_id,
                "skill": skill,
                "sandbox_path": sandbox_path,
                "workspace_path": workspace_path,
                "tools": tools,
                "status": "active",
                "isolation_mode": self.isolation_mode,
                "container_id": container_id,
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
        result = {
            "sandbox_id": sandbox_info["sandbox_id"],
            "skill_name": skill.name,
            "skill_description": skill.description,
            "sandbox_path": str(sandbox_info["sandbox_path"]),
            "workspace_path": str(sandbox_info["workspace_path"]),
            "tools": list(sandbox_info["tools"].keys()),
            "status": sandbox_info["status"],
            "isolation_mode": sandbox_info.get("isolation_mode", "container"),
        }
        
        # Add container_id if in container mode
        if sandbox_info.get("isolation_mode") == "container":
            result["container_id"] = sandbox_info.get("container_id")
        
        return result
    
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
        
        # Route to appropriate execution method based on isolation mode
        if sandbox_info["isolation_mode"] == "container":
            # Execute via container executor
            if self.container_executor is None:
                raise RuntimeError(
                    "Container executor not initialized. "
                    "This should not happen if isolation_mode='container'."
                )
            
            container_id = sandbox_info.get("container_id")
            if container_id is None:
                raise RuntimeError(
                    f"Container ID not found for sandbox {sandbox_id}. "
                    "Container may not have been created properly."
                )
            
            try:
                return self.container_executor.execute_tool(
                    container_id, tool_name, kwargs
                )
            except Exception as e:
                raise RuntimeError(
                    f"Tool execution failed for '{tool_name}' in sandbox {sandbox_id}: {e}"
                ) from e
        else:
            # Execute directly (directory mode)
            tool = sandbox_info["tools"][tool_name]
            if tool is None:
                raise ValueError(
                    f"Tool '{tool_name}' instance not available in sandbox {sandbox_id}"
                )
            
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
            
            # Clean up environment based on isolation mode
            if sandbox_info["isolation_mode"] == "container":
                if self.container_environment_builder is None:
                    logger.warning(
                        f"Container environment builder not available for cleanup "
                        f"of sandbox {sandbox_id}"
                    )
                else:
                    self.container_environment_builder.cleanup(sandbox_id)
            else:
                # Directory-based cleanup
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
