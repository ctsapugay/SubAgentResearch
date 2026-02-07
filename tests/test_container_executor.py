"""Tests for ContainerToolExecutor."""

import json
from unittest.mock import MagicMock, Mock

import pytest

from src.sandbox.container_executor import ContainerToolExecutor


class MockContainerManager:
    """Mock container manager for testing."""
    
    def __init__(self):
        self.executions = []
    
    def execute_in_container(
        self,
        container_id: str,
        command: list[str],
        timeout: int = 30
    ) -> dict:
        """Mock execute_in_container method."""
        self.executions.append({
            "container_id": container_id,
            "command": command,
            "timeout": timeout
        })
        
        # Return mock result - will be overridden in tests
        return {
            "exit_code": 0,
            "stdout": "",
            "stderr": "",
            "error": None
        }


@pytest.fixture
def mock_container_manager():
    """Create a mock container manager."""
    return MockContainerManager()


@pytest.fixture
def executor(mock_container_manager):
    """Create a ContainerToolExecutor instance."""
    return ContainerToolExecutor(mock_container_manager)


class TestContainerToolExecutor:
    """Tests for ContainerToolExecutor class."""
    
    def test_init(self, mock_container_manager):
        """Test executor initialization."""
        executor = ContainerToolExecutor(mock_container_manager)
        assert executor.container_manager == mock_container_manager
        assert executor.default_timeout == 30
        
        # Test with custom timeout
        executor2 = ContainerToolExecutor(mock_container_manager, default_timeout=60)
        assert executor2.default_timeout == 60
    
    def test_create_tool_script_read_file(self, executor):
        """Test script generation for read_file tool."""
        tool_args = {"file_path": "test.txt"}
        script = executor._create_tool_script("read_file", tool_args)
        
        assert "from src.tools.implementations.filesystem import ReadFileTool" in script
        assert "ReadFileTool(base_path=\"/workspace\")" in script
        assert "json.loads" in script
        assert "tool.execute(**tool_args)" in script
        assert "json.dumps" in script
    
    def test_create_tool_script_write_file(self, executor):
        """Test script generation for write_file tool."""
        tool_args = {"file_path": "test.txt", "content": "Hello"}
        script = executor._create_tool_script("write_file", tool_args)
        
        assert "WriteFileTool" in script
        assert "file_path" in script or json.dumps(tool_args) in script
    
    def test_create_tool_script_list_files(self, executor):
        """Test script generation for list_files tool."""
        tool_args = {"directory_path": "."}
        script = executor._create_tool_script("list_files", tool_args)
        
        assert "ListFilesTool" in script
    
    def test_create_tool_script_with_complex_args(self, executor):
        """Test script generation with complex arguments."""
        tool_args = {
            "file_path": "test.txt",
            "content": "Line 1\nLine 2\nLine 3"
        }
        script = executor._create_tool_script("write_file", tool_args)
        
        # Script should handle multi-line strings
        assert "json.loads" in script
        # Verify arguments are properly serialized
        assert json.dumps(tool_args) in script or "file_path" in script
    
    def test_execute_script_in_container_success(self, executor, mock_container_manager):
        """Test successful script execution."""
        script = "print('test')"
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": 0,
                "stdout": '{"success": True, "result": "test"}',
                "stderr": "",
                "error": None
            }
        )
        
        result = executor._execute_script_in_container("container-123", script, 30)
        
        assert result["exit_code"] == 0
        assert "success" in result["stdout"]
        mock_container_manager.execute_in_container.assert_called_once()
    
    def test_execute_script_in_container_error(self, executor, mock_container_manager):
        """Test script execution with container error."""
        script = "print('test')"
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": 0,
                "stdout": "",
                "stderr": "",
                "error": "Container not found"
            }
        )
        
        with pytest.raises(RuntimeError, match="Container execution error"):
            executor._execute_script_in_container("container-123", script, 30)
    
    def test_execute_script_in_container_non_zero_exit(self, executor, mock_container_manager):
        """Test script execution with non-zero exit code."""
        script = "print('test')"
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": 1,
                "stdout": "",
                "stderr": "Python error",
                "error": None
            }
        )
        
        with pytest.raises(RuntimeError, match="Tool execution failed with exit code"):
            executor._execute_script_in_container("container-123", script, 30)
    
    def test_deserialize_result_success(self, executor):
        """Test successful result deserialization."""
        execution_result = {
            "exit_code": 0,
            "stdout": json.dumps({"success": True, "result": "file content"}),
            "stderr": "",
            "error": None
        }
        
        result = executor._deserialize_result(execution_result)
        assert result == "file content"
    
    def test_deserialize_result_dict(self, executor):
        """Test deserialization of dict result."""
        result_dict = {"file": "test.txt", "size": 100}
        execution_result = {
            "exit_code": 0,
            "stdout": json.dumps({"success": True, "result": result_dict}),
            "stderr": "",
            "error": None
        }
        
        result = executor._deserialize_result(execution_result)
        assert result == result_dict
    
    def test_deserialize_result_list(self, executor):
        """Test deserialization of list result."""
        result_list = ["file1.txt", "file2.txt"]
        execution_result = {
            "exit_code": 0,
            "stdout": json.dumps({"success": True, "result": result_list}),
            "stderr": "",
            "error": None
        }
        
        result = executor._deserialize_result(execution_result)
        assert result == result_list
    
    def test_deserialize_result_empty_stdout(self, executor):
        """Test deserialization with empty stdout."""
        execution_result = {
            "exit_code": 0,
            "stdout": "",
            "stderr": "Some error",
            "error": None
        }
        
        with pytest.raises(RuntimeError, match="Tool execution produced no output"):
            executor._deserialize_result(execution_result)
    
    def test_deserialize_result_invalid_json(self, executor):
        """Test deserialization with invalid JSON."""
        execution_result = {
            "exit_code": 0,
            "stdout": "not json",
            "stderr": "",
            "error": None
        }
        
        with pytest.raises(RuntimeError, match="Failed to parse tool output as JSON"):
            executor._deserialize_result(execution_result)
    
    def test_deserialize_result_tool_failure(self, executor):
        """Test deserialization when tool execution failed."""
        error_info = {
            "error": "File not found",
            "type": "FileNotFoundError",
            "traceback": "Traceback..."
        }
        execution_result = {
            "exit_code": 0,
            "stdout": json.dumps({"success": False, "error": error_info}),
            "stderr": "",
            "error": None
        }
        
        with pytest.raises(RuntimeError, match="Tool execution failed"):
            executor._deserialize_result(execution_result)
    
    def test_deserialize_result_tool_failure_string_error(self, executor):
        """Test deserialization with string error message."""
        execution_result = {
            "exit_code": 0,
            "stdout": json.dumps({"success": False, "error": "Simple error"}),
            "stderr": "",
            "error": None
        }
        
        with pytest.raises(RuntimeError, match="Simple error"):
            executor._deserialize_result(execution_result)
    
    def test_execute_tool_read_file(self, executor, mock_container_manager):
        """Test executing read_file tool."""
        tool_args = {"file_path": "test.txt"}
        
        # Mock successful execution
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": 0,
                "stdout": json.dumps({
                    "success": True,
                    "result": "file content here"
                }),
                "stderr": "",
                "error": None
            }
        )
        
        result = executor.execute_tool("container-123", "read_file", tool_args)
        
        assert result == "file content here"
        mock_container_manager.execute_in_container.assert_called_once()
        
        # Verify command structure
        call_args = mock_container_manager.execute_in_container.call_args
        assert call_args[0][0] == "container-123"
        assert call_args[0][1][0] == "python"
        assert call_args[0][1][1] == "-c"
    
    def test_execute_tool_write_file(self, executor, mock_container_manager):
        """Test executing write_file tool."""
        tool_args = {"file_path": "test.txt", "content": "Hello World"}
        
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": 0,
                "stdout": json.dumps({
                    "success": True,
                    "result": {"success": True, "file_path": "test.txt", "bytes_written": 11}
                }),
                "stderr": "",
                "error": None
            }
        )
        
        result = executor.execute_tool("container-123", "write_file", tool_args)
        
        assert result["success"] is True
        assert result["file_path"] == "test.txt"
    
    def test_execute_tool_unknown_tool(self, executor):
        """Test executing unknown tool."""
        with pytest.raises(ValueError, match="Unknown tool"):
            executor.execute_tool("container-123", "unknown_tool", {})
    
    def test_execute_tool_custom_timeout(self, executor, mock_container_manager):
        """Test executing tool with custom timeout."""
        tool_args = {"file_path": "test.txt"}
        
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": 0,
                "stdout": json.dumps({"success": True, "result": "content"}),
                "stderr": "",
                "error": None
            }
        )
        
        executor.execute_tool("container-123", "read_file", tool_args, timeout=60)
        
        # Verify timeout was passed
        call_args = mock_container_manager.execute_in_container.call_args
        assert call_args[1]["timeout"] == 60
    
    def test_execute_tool_timeout_error(self, executor, mock_container_manager):
        """Test tool execution timeout."""
        tool_args = {"file_path": "test.txt"}
        
        mock_container_manager.execute_in_container = Mock(
            return_value={
                "exit_code": -1,
                "stdout": "",
                "stderr": "",
                "error": "Timeout"
            }
        )
        
        with pytest.raises(RuntimeError, match="Container execution error"):
            executor.execute_tool("container-123", "read_file", tool_args, timeout=5)
    
    def test_get_tool_class_name(self, executor):
        """Test getting tool class name."""
        assert executor._get_tool_class_name("read_file") == "ReadFileTool"
        assert executor._get_tool_class_name("write_file") == "WriteFileTool"
        assert executor._get_tool_class_name("list_files") == "ListFilesTool"
    
    def test_get_tool_class_name_unknown(self, executor):
        """Test getting class name for unknown tool."""
        with pytest.raises(ValueError, match="Unknown tool"):
            executor._get_tool_class_name("unknown_tool")
    
    def test_script_handles_special_characters(self, executor):
        """Test script generation handles special characters in arguments."""
        tool_args = {
            "file_path": "test.txt",
            "content": "Line with 'quotes' and \"double quotes\" and\nnewlines"
        }
        
        script = executor._create_tool_script("write_file", tool_args)
        
        # Script should be valid Python
        assert "json.loads" in script
        # Arguments should be properly escaped via JSON
        assert json.dumps(tool_args) in script or "file_path" in script
    
    def test_script_error_handling(self, executor):
        """Test that script includes proper error handling."""
        script = executor._create_tool_script("read_file", {"file_path": "test.txt"})
        
        assert "try:" in script
        assert "except Exception" in script
        assert "traceback" in script
        assert "json.dumps" in script
        assert '"success": False' in script
