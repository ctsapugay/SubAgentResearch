"""Tool executor for running tools within Docker containers."""

import json
import sys
from typing import Any, Dict, Optional, Protocol

from src.tools.registry import ToolRegistry


class ContainerManagerProtocol(Protocol):
    """Protocol defining the interface required from ContainerManager.
    
    This allows ContainerToolExecutor to work with any object that implements
    the execute_in_container method, enabling easier testing and future changes.
    """
    
    def execute_in_container(
        self,
        container_id: str,
        command: list[str],
        timeout: int = 30
    ) -> Dict[str, Any]:
        """Execute a command in a container.
        
        Args:
            container_id: ID of the container to execute in
            command: Command to execute as a list of strings
            timeout: Timeout in seconds
            
        Returns:
            Dictionary with keys:
                - exit_code: int
                - stdout: str
                - stderr: str
                - error: Optional[str]
        """
        ...


class ContainerToolExecutor:
    """Executes tools within Docker containers.
    
    This class handles the serialization, execution, and deserialization
    of tool calls within isolated Docker containers.
    """
    
    # Mapping of tool names to their class names for imports
    TOOL_CLASS_MAP = {
        "read_file": "ReadFileTool",
        "write_file": "WriteFileTool",
        "list_files": "ListFilesTool",
    }
    
    def __init__(
        self,
        container_manager: ContainerManagerProtocol,
        tool_registry: Optional[ToolRegistry] = None,
        default_timeout: int = 30
    ):
        """Initialize the container tool executor.
        
        Args:
            container_manager: Container manager that can execute commands
            tool_registry: Optional tool registry for tool information
            default_timeout: Default timeout for tool execution in seconds
        """
        self.container_manager = container_manager
        self.tool_registry = tool_registry or ToolRegistry()
        self.default_timeout = default_timeout
    
    def execute_tool(
        self,
        container_id: str,
        tool_name: str,
        tool_args: Dict[str, Any],
        timeout: Optional[int] = None
    ) -> Any:
        """Execute a tool within a container.
        
        Args:
            container_id: ID of the container to execute in
            tool_name: Name of the tool to execute
            tool_args: Arguments for the tool
            timeout: Optional timeout override (uses default if not provided)
            
        Returns:
            Tool execution result (deserialized from JSON)
            
        Raises:
            ValueError: If tool_name is not recognized
            RuntimeError: If tool execution fails or times out
        """
        if tool_name not in self.TOOL_CLASS_MAP:
            raise ValueError(
                f"Unknown tool: {tool_name}. "
                f"Available tools: {list(self.TOOL_CLASS_MAP.keys())}"
            )
        
        # Generate Python script to execute the tool
        script = self._create_tool_script(tool_name, tool_args)
        
        # Execute script in container
        exec_timeout = timeout if timeout is not None else self.default_timeout
        result = self._execute_script_in_container(
            container_id,
            script,
            exec_timeout
        )
        
        # Deserialize and return result
        return self._deserialize_result(result)
    
    def _create_tool_script(
        self,
        tool_name: str,
        tool_args: Dict[str, Any]
    ) -> str:
        """Create Python script to execute a tool.
        
        Args:
            tool_name: Name of the tool to execute
            tool_args: Arguments for the tool
            
        Returns:
            Python script as a string
        """
        tool_class_name = self.TOOL_CLASS_MAP[tool_name]
        
        # Escape tool_args for safe inclusion in Python code
        # Use json.dumps to safely serialize the arguments
        tool_args_json = json.dumps(tool_args)
        
        script = f"""import json
import sys
from pathlib import Path

# Import tool class
from src.tools.implementations.filesystem import {tool_class_name}

# Create tool instance with workspace path
tool = {tool_class_name}(base_path="/workspace")

# Parse tool arguments from JSON
tool_args = json.loads({repr(tool_args_json)})

# Execute tool
try:
    result = tool.execute(**tool_args)
    
    # Serialize result
    # Handle different result types
    if isinstance(result, (dict, list, str, int, float, bool, type(None))):
        output = json.dumps({{"success": True, "result": result}})
    else:
        # For other types, convert to string
        output = json.dumps({{"success": True, "result": str(result)}})
        
except Exception as e:
    # Capture exception information
    import traceback
    error_info = {{
        "error": str(e),
        "type": type(e).__name__,
        "traceback": traceback.format_exc()
    }}
    output = json.dumps({{"success": False, "error": error_info}})

# Output result to stdout
print(output)
sys.stdout.flush()
"""
        return script
    
    def _execute_script_in_container(
        self,
        container_id: str,
        script: str,
        timeout: int
    ) -> Dict[str, Any]:
        """Execute a Python script in a container.
        
        Args:
            container_id: ID of the container
            script: Python script to execute
            timeout: Timeout in seconds
            
        Returns:
            Execution result dictionary from container_manager
            
        Raises:
            RuntimeError: If execution fails or times out
        """
        # Create command to execute Python script
        # Use python -c to execute the script
        command = ["python", "-c", script]
        
        # Execute in container
        result = self.container_manager.execute_in_container(
            container_id,
            command,
            timeout=timeout
        )
        
        # Check for execution errors
        if result.get("error"):
            raise RuntimeError(
                f"Container execution error: {result['error']}"
            )
        
        # Check exit code
        exit_code = result.get("exit_code", -1)
        if exit_code != 0:
            stderr = result.get("stderr", "")
            raise RuntimeError(
                f"Tool execution failed with exit code {exit_code}. "
                f"Error: {stderr}"
            )
        
        return result
    
    def _deserialize_result(self, execution_result: Dict[str, Any]) -> Any:
        """Deserialize tool execution result from container output.
        
        Args:
            execution_result: Result dictionary from container execution
            
        Returns:
            Deserialized tool result
            
        Raises:
            RuntimeError: If result cannot be deserialized or indicates failure
        """
        stdout = execution_result.get("stdout", "").strip()
        
        if not stdout:
            raise RuntimeError(
                "Tool execution produced no output. "
                f"Stderr: {execution_result.get('stderr', '')}"
            )
        
        try:
            # Parse JSON output from tool script
            output_data = json.loads(stdout)
        except json.JSONDecodeError as e:
            raise RuntimeError(
                f"Failed to parse tool output as JSON: {e}. "
                f"Output: {stdout[:200]}"
            )
        
        # Check if execution was successful
        if not output_data.get("success", False):
            error_info = output_data.get("error", {})
            if isinstance(error_info, dict):
                error_msg = error_info.get("error", "Unknown error")
                error_type = error_info.get("type", "Exception")
                traceback_str = error_info.get("traceback", "")
                
                # Reconstruct exception message
                full_error = f"{error_type}: {error_msg}"
                if traceback_str:
                    full_error += f"\n{traceback_str}"
                
                raise RuntimeError(f"Tool execution failed: {full_error}")
            else:
                raise RuntimeError(
                    f"Tool execution failed: {error_info}"
                )
        
        # Return the actual result
        return output_data.get("result")
    
    def _get_tool_class_name(self, tool_name: str) -> str:
        """Get the class name for a tool.
        
        Args:
            tool_name: Name of the tool
            
        Returns:
            Class name for the tool
            
        Raises:
            ValueError: If tool_name is not recognized
        """
        if tool_name not in self.TOOL_CLASS_MAP:
            raise ValueError(
                f"Unknown tool: {tool_name}. "
                f"Available tools: {list(self.TOOL_CLASS_MAP.keys())}"
            )
        
        return self.TOOL_CLASS_MAP[tool_name]
