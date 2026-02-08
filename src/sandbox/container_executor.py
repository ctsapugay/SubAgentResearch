"""Tool executor for running tools within Docker containers.

Generates self-contained Python scripts that are executed inside containers.
The scripts must NOT import any project modules (the ``src`` package is not
available inside the container image).  All tool logic is therefore inlined
in the generated scripts.
"""

import json
import logging
import sys
from typing import Any, Dict, Optional, Protocol

from src.tools.registry import ToolRegistry

logger = logging.getLogger(__name__)


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
    
    The generated scripts are fully self-contained — they do NOT depend on
    the host project's ``src`` package being present inside the container.
    """
    
    # Tools that are supported for in-container execution
    SUPPORTED_TOOLS = {"read_file", "write_file", "list_files"}
    
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
        if tool_name not in self.SUPPORTED_TOOLS:
            raise ValueError(
                f"Unknown tool: {tool_name}. "
                f"Available tools: {sorted(self.SUPPORTED_TOOLS)}"
            )
        
        # Generate self-contained Python script to execute the tool
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
    
    # ------------------------------------------------------------------
    # Script generators
    # ------------------------------------------------------------------
    # Each tool gets a self-contained script that only uses the Python
    # standard library.  This is critical because the project's ``src``
    # package is NOT installed inside the container image.
    # ------------------------------------------------------------------

    def _create_tool_script(
        self,
        tool_name: str,
        tool_args: Dict[str, Any]
    ) -> str:
        """Create a self-contained Python script to execute a tool.
        
        The generated script uses **only** the Python standard library so
        it can run inside a bare ``python:3.x-slim`` container without any
        additional dependencies.
        
        Args:
            tool_name: Name of the tool to execute
            tool_args: Arguments for the tool
            
        Returns:
            Python script as a string
        """
        generator = {
            "write_file": self._script_write_file,
            "read_file": self._script_read_file,
            "list_files": self._script_list_files,
        }.get(tool_name)

        if generator is None:
            raise ValueError(
                f"No script generator for tool: {tool_name}. "
                f"Available tools: {sorted(self.SUPPORTED_TOOLS)}"
            )

        return generator(tool_args)

    # --- individual script generators -----------------------------------

    @staticmethod
    def _script_write_file(tool_args: Dict[str, Any]) -> str:
        """Generate a self-contained script that writes a file."""
        args_json = json.dumps(tool_args)
        return f"""import json, os, sys
from pathlib import Path

BASE = Path("/workspace")
args = json.loads({repr(args_json)})

file_path = args.get("file_path", "")
content   = args.get("content", "")

if not file_path or not isinstance(file_path, str):
    print(json.dumps({{"success": False, "error": {{"error": "Missing or invalid file_path", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

if not isinstance(content, str):
    print(json.dumps({{"success": False, "error": {{"error": "content must be a string", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

target = (BASE / file_path).resolve()

# Prevent directory traversal outside /workspace
try:
    target.relative_to(BASE)
except ValueError:
    print(json.dumps({{"success": False, "error": {{"error": f"Path {{file_path}} is outside sandbox /workspace", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

try:
    target.parent.mkdir(parents=True, exist_ok=True)
    with open(target, "w", encoding="utf-8") as f:
        bytes_written = f.write(content)
    print(json.dumps({{"success": True, "result": {{"success": True, "file_path": str(target), "bytes_written": bytes_written}}}}))
except Exception as e:
    import traceback as tb
    print(json.dumps({{"success": False, "error": {{"error": str(e), "type": type(e).__name__, "traceback": tb.format_exc()}}}}))

sys.stdout.flush()
"""

    @staticmethod
    def _script_read_file(tool_args: Dict[str, Any]) -> str:
        """Generate a self-contained script that reads a file."""
        args_json = json.dumps(tool_args)
        return f"""import json, sys
from pathlib import Path

BASE = Path("/workspace")
args = json.loads({repr(args_json)})

file_path = args.get("file_path", "")

if not file_path or not isinstance(file_path, str):
    print(json.dumps({{"success": False, "error": {{"error": "Missing or invalid file_path", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

target = (BASE / file_path).resolve()

try:
    target.relative_to(BASE)
except ValueError:
    print(json.dumps({{"success": False, "error": {{"error": f"Path {{file_path}} is outside sandbox /workspace", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

try:
    if not target.exists():
        raise FileNotFoundError(f"File not found: {{target}}")
    if not target.is_file():
        raise ValueError(f"Path is not a file: {{target}}")
    with open(target, "r", encoding="utf-8") as f:
        content = f.read()
    print(json.dumps({{"success": True, "result": content}}))
except Exception as e:
    import traceback as tb
    print(json.dumps({{"success": False, "error": {{"error": str(e), "type": type(e).__name__, "traceback": tb.format_exc()}}}}))

sys.stdout.flush()
"""

    @staticmethod
    def _script_list_files(tool_args: Dict[str, Any]) -> str:
        """Generate a self-contained script that lists files in a directory."""
        args_json = json.dumps(tool_args)
        return f"""import json, sys
from pathlib import Path

BASE = Path("/workspace")
args = json.loads({repr(args_json)})

directory_path = args.get("directory_path", ".")

if not isinstance(directory_path, str):
    print(json.dumps({{"success": False, "error": {{"error": "directory_path must be a string", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

target = (BASE / directory_path).resolve()

try:
    target.relative_to(BASE)
except ValueError:
    print(json.dumps({{"success": False, "error": {{"error": f"Path {{directory_path}} is outside sandbox /workspace", "type": "ValueError", "traceback": ""}}}}))
    sys.exit(0)

try:
    if not target.exists():
        raise FileNotFoundError(f"Directory not found: {{target}}")
    if not target.is_dir():
        raise ValueError(f"Path is not a directory: {{target}}")
    items = sorted(item.name for item in target.iterdir())
    print(json.dumps({{"success": True, "result": items}}))
except Exception as e:
    import traceback as tb
    print(json.dumps({{"success": False, "error": {{"error": str(e), "type": type(e).__name__, "traceback": tb.format_exc()}}}}))

sys.stdout.flush()
"""
    
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
        
        # Check for execution errors — include stdout/stderr so the real
        # failure reason (e.g. ImportError inside the container) is visible.
        stdout = result.get("stdout", "")
        stderr = result.get("stderr", "")
        
        if result.get("error"):
            raise RuntimeError(
                f"Container execution error: {result['error']}\n"
                f"stdout: {stdout}\n"
                f"stderr: {stderr}"
            )
        
        # Check exit code
        exit_code = result.get("exit_code", -1)
        if exit_code != 0:
            raise RuntimeError(
                f"Tool execution failed with exit code {exit_code}.\n"
                f"stdout: {stdout}\n"
                f"stderr: {stderr}"
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
    
    def _get_supported_tools(self) -> list:
        """Get list of supported tool names.
        
        Returns:
            Sorted list of supported tool names
        """
        return sorted(self.SUPPORTED_TOOLS)
