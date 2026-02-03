"""Filesystem tools for reading, writing, and listing files within sandboxes."""

import os
from pathlib import Path
from typing import Any, Dict, List

from src.tools.base import ToolBase


class ReadFileTool(ToolBase):
    """Tool for reading files within a sandbox workspace.
    
    Ensures all file operations are restricted to the sandbox directory
    to prevent directory traversal attacks.
    """
    
    def __init__(self, base_path: str = "/sandbox"):
        """Initialize the read file tool.
        
        Args:
            base_path: Base directory path for the sandbox workspace
        """
        super().__init__(
            name="read_file",
            description="Read content from a file in the sandbox workspace"
        )
        self.base_path = Path(base_path).resolve()
    
    def validate_parameters(self, **kwargs) -> bool:
        """Validate that file_path parameter is provided.
        
        Args:
            **kwargs: Must contain 'file_path' key
            
        Returns:
            True if valid, False otherwise
        """
        if "file_path" not in kwargs:
            return False
        file_path = kwargs["file_path"]
        if not isinstance(file_path, str):
            return False
        if not file_path:
            return False
        return True
    
    def _ensure_within_sandbox(self, file_path: str) -> Path:
        """Ensure the file path is within the sandbox.
        
        Args:
            file_path: Relative or absolute file path
            
        Returns:
            Resolved Path object within sandbox
            
        Raises:
            ValueError: If path is outside sandbox
        """
        # Check if it's an absolute path first
        path_obj = Path(file_path)
        if path_obj.is_absolute():
            # Absolute path - check if it's within base_path
            requested_path = path_obj.resolve()
            try:
                requested_path.relative_to(self.base_path)
            except ValueError:
                raise ValueError(
                    f"Path {file_path} is outside sandbox directory {self.base_path}"
                )
        else:
            # Relative path - resolve relative to base_path
            requested_path = (self.base_path / file_path).resolve()
            # Double-check it's still within sandbox (handles .. traversal)
            try:
                requested_path.relative_to(self.base_path)
            except ValueError:
                raise ValueError(
                    f"Path {file_path} resolves outside sandbox directory {self.base_path}"
                )
        
        return requested_path
    
    def execute(self, **kwargs) -> str:
        """Read a file and return its contents.
        
        Args:
            file_path: Path to the file to read (relative to sandbox or absolute)
            
        Returns:
            File contents as a string
            
        Raises:
            ValueError: If parameters are invalid or path is outside sandbox
            FileNotFoundError: If file doesn't exist
            PermissionError: If file cannot be read
        """
        if not self.validate_parameters(**kwargs):
            raise ValueError("Missing or invalid 'file_path' parameter")
        
        file_path = kwargs["file_path"]
        resolved_path = self._ensure_within_sandbox(file_path)
        
        if not resolved_path.exists():
            raise FileNotFoundError(f"File not found: {resolved_path}")
        
        if not resolved_path.is_file():
            raise ValueError(f"Path is not a file: {resolved_path}")
        
        try:
            with open(resolved_path, "r", encoding="utf-8") as f:
                return f.read()
        except PermissionError as e:
            raise PermissionError(f"Cannot read file {resolved_path}: {e}")


class WriteFileTool(ToolBase):
    """Tool for writing files within a sandbox workspace.
    
    Creates parent directories as needed and ensures all file operations
    are restricted to the sandbox directory.
    """
    
    def __init__(self, base_path: str = "/sandbox"):
        """Initialize the write file tool.
        
        Args:
            base_path: Base directory path for the sandbox workspace
        """
        super().__init__(
            name="write_file",
            description="Write content to a file in the sandbox workspace"
        )
        self.base_path = Path(base_path).resolve()
    
    def validate_parameters(self, **kwargs) -> bool:
        """Validate that file_path and content parameters are provided.
        
        Args:
            **kwargs: Must contain 'file_path' and 'content' keys
            
        Returns:
            True if valid, False otherwise
        """
        if "file_path" not in kwargs:
            return False
        if "content" not in kwargs:
            return False
        
        file_path = kwargs["file_path"]
        if not isinstance(file_path, str):
            return False
        if not file_path:
            return False
        
        content = kwargs["content"]
        if not isinstance(content, str):
            return False
        
        return True
    
    def _ensure_within_sandbox(self, file_path: str) -> Path:
        """Ensure the file path is within the sandbox.
        
        Args:
            file_path: Relative or absolute file path
            
        Returns:
            Resolved Path object within sandbox
            
        Raises:
            ValueError: If path is outside sandbox
        """
        # Check if it's an absolute path first
        path_obj = Path(file_path)
        if path_obj.is_absolute():
            # Absolute path - check if it's within base_path
            requested_path = path_obj.resolve()
            try:
                requested_path.relative_to(self.base_path)
            except ValueError:
                raise ValueError(
                    f"Path {file_path} is outside sandbox directory {self.base_path}"
                )
        else:
            # Relative path - resolve relative to base_path
            requested_path = (self.base_path / file_path).resolve()
            # Double-check it's still within sandbox (handles .. traversal)
            try:
                requested_path.relative_to(self.base_path)
            except ValueError:
                raise ValueError(
                    f"Path {file_path} resolves outside sandbox directory {self.base_path}"
                )
        
        return requested_path
    
    def execute(self, **kwargs) -> Dict[str, Any]:
        """Write content to a file.
        
        Args:
            file_path: Path to the file to write (relative to sandbox or absolute)
            content: Content to write to the file
            
        Returns:
            Dictionary with success status, file_path, and bytes_written
            
        Raises:
            ValueError: If parameters are invalid or path is outside sandbox
            PermissionError: If file cannot be written
        """
        if not self.validate_parameters(**kwargs):
            raise ValueError("Missing or invalid 'file_path' or 'content' parameters")
        
        file_path = kwargs["file_path"]
        content = kwargs["content"]
        
        resolved_path = self._ensure_within_sandbox(file_path)
        
        # Create parent directories if they don't exist
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        
        try:
            with open(resolved_path, "w", encoding="utf-8") as f:
                bytes_written = f.write(content)
            
            return {
                "success": True,
                "file_path": str(resolved_path),
                "bytes_written": bytes_written
            }
        except PermissionError as e:
            raise PermissionError(f"Cannot write file {resolved_path}: {e}")


class ListFilesTool(ToolBase):
    """Tool for listing files in a directory within a sandbox workspace.
    
    Lists files and directories in the specified directory, ensuring
    all operations are restricted to the sandbox.
    """
    
    def __init__(self, base_path: str = "/sandbox"):
        """Initialize the list files tool.
        
        Args:
            base_path: Base directory path for the sandbox workspace
        """
        super().__init__(
            name="list_files",
            description="List files and directories in a sandbox workspace directory"
        )
        self.base_path = Path(base_path).resolve()
    
    def validate_parameters(self, **kwargs) -> bool:
        """Validate parameters.
        
        Args:
            **kwargs: May contain optional 'directory_path' key
            
        Returns:
            True if valid, False otherwise
        """
        # directory_path is optional, defaults to "."
        if "directory_path" in kwargs:
            directory_path = kwargs["directory_path"]
            if not isinstance(directory_path, str):
                return False
        return True
    
    def _ensure_within_sandbox(self, directory_path: str) -> Path:
        """Ensure the directory path is within the sandbox.
        
        Args:
            directory_path: Relative or absolute directory path
            
        Returns:
            Resolved Path object within sandbox
            
        Raises:
            ValueError: If path is outside sandbox
        """
        # Check if it's an absolute path first
        path_obj = Path(directory_path)
        if path_obj.is_absolute():
            # Absolute path - check if it's within base_path
            requested_path = path_obj.resolve()
            try:
                requested_path.relative_to(self.base_path)
            except ValueError:
                raise ValueError(
                    f"Path {directory_path} is outside sandbox directory {self.base_path}"
                )
        else:
            # Relative path - resolve relative to base_path
            requested_path = (self.base_path / directory_path).resolve()
            # Double-check it's still within sandbox (handles .. traversal)
            try:
                requested_path.relative_to(self.base_path)
            except ValueError:
                raise ValueError(
                    f"Path {directory_path} resolves outside sandbox directory {self.base_path}"
                )
        
        return requested_path
    
    def execute(self, **kwargs) -> List[str]:
        """List files and directories in a directory.
        
        Args:
            directory_path: Path to the directory (relative to sandbox or absolute).
                          Defaults to "." (current directory).
            
        Returns:
            List of filenames and directory names in the directory
            
        Raises:
            ValueError: If parameters are invalid or path is outside sandbox
            FileNotFoundError: If directory doesn't exist
            PermissionError: If directory cannot be read
        """
        if not self.validate_parameters(**kwargs):
            raise ValueError("Invalid 'directory_path' parameter")
        
        directory_path = kwargs.get("directory_path", ".")
        resolved_path = self._ensure_within_sandbox(directory_path)
        
        if not resolved_path.exists():
            raise FileNotFoundError(f"Directory not found: {resolved_path}")
        
        if not resolved_path.is_dir():
            raise ValueError(f"Path is not a directory: {resolved_path}")
        
        try:
            # List all items in the directory
            items = []
            for item in sorted(resolved_path.iterdir()):
                # Return just the name, not the full path
                items.append(item.name)
            return items
        except PermissionError as e:
            raise PermissionError(f"Cannot list directory {resolved_path}: {e}")
