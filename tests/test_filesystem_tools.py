"""Tests for filesystem tools."""

import os
import tempfile
from pathlib import Path

import pytest

from src.tools.implementations.filesystem import (
    ListFilesTool,
    ReadFileTool,
    WriteFileTool,
)


class TestReadFileTool:
    """Test cases for ReadFileTool."""
    
    def test_initialization(self):
        """Test tool initialization."""
        tool = ReadFileTool(base_path="/sandbox")
        assert tool.name == "read_file"
        assert tool.base_path == Path("/sandbox").resolve()
    
    def test_validate_parameters_valid(self):
        """Test parameter validation with valid input."""
        tool = ReadFileTool()
        assert tool.validate_parameters(file_path="test.txt") is True
    
    def test_validate_parameters_missing_file_path(self):
        """Test parameter validation with missing file_path."""
        tool = ReadFileTool()
        assert tool.validate_parameters() is False
    
    def test_validate_parameters_invalid_type(self):
        """Test parameter validation with invalid type."""
        tool = ReadFileTool()
        assert tool.validate_parameters(file_path=123) is False
        assert tool.validate_parameters(file_path="") is False
    
    def test_read_file_success(self):
        """Test successfully reading a file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ReadFileTool(base_path=tmpdir)
            test_file = Path(tmpdir) / "test.txt"
            test_file.write_text("Hello, World!")
            
            content = tool.execute(file_path="test.txt")
            assert content == "Hello, World!"
    
    def test_read_file_absolute_path(self):
        """Test reading file with absolute path."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ReadFileTool(base_path=tmpdir)
            test_file = Path(tmpdir) / "test.txt"
            test_file.write_text("Content")
            
            content = tool.execute(file_path=str(test_file))
            assert content == "Content"
    
    def test_read_file_not_found(self):
        """Test reading non-existent file raises FileNotFoundError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ReadFileTool(base_path=tmpdir)
            with pytest.raises(FileNotFoundError):
                tool.execute(file_path="nonexistent.txt")
    
    def test_read_file_outside_sandbox_raises_error(self):
        """Test that reading file outside sandbox raises ValueError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ReadFileTool(base_path=tmpdir)
            with tempfile.TemporaryDirectory() as other_dir:
                other_file = Path(other_dir) / "test.txt"
                other_file.write_text("Content")
                
                with pytest.raises(ValueError, match="outside sandbox"):
                    tool.execute(file_path=str(other_file))
    
    def test_read_file_path_traversal_raises_error(self):
        """Test that path traversal attempts are blocked."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ReadFileTool(base_path=tmpdir)
            with pytest.raises(ValueError, match="outside sandbox"):
                tool.execute(file_path="../../etc/passwd")
    
    def test_read_directory_raises_error(self):
        """Test that reading a directory raises ValueError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ReadFileTool(base_path=tmpdir)
            Path(tmpdir).joinpath("subdir").mkdir()
            
            with pytest.raises(ValueError, match="not a file"):
                tool.execute(file_path="subdir")


class TestWriteFileTool:
    """Test cases for WriteFileTool."""
    
    def test_initialization(self):
        """Test tool initialization."""
        tool = WriteFileTool(base_path="/sandbox")
        assert tool.name == "write_file"
        assert tool.base_path == Path("/sandbox").resolve()
    
    def test_validate_parameters_valid(self):
        """Test parameter validation with valid input."""
        tool = WriteFileTool()
        assert tool.validate_parameters(
            file_path="test.txt", content="Hello"
        ) is True
    
    def test_validate_parameters_missing_file_path(self):
        """Test parameter validation with missing file_path."""
        tool = WriteFileTool()
        assert tool.validate_parameters(content="Hello") is False
    
    def test_validate_parameters_missing_content(self):
        """Test parameter validation with missing content."""
        tool = WriteFileTool()
        assert tool.validate_parameters(file_path="test.txt") is False
    
    def test_validate_parameters_invalid_types(self):
        """Test parameter validation with invalid types."""
        tool = WriteFileTool()
        assert tool.validate_parameters(
            file_path=123, content="Hello"
        ) is False
        assert tool.validate_parameters(
            file_path="test.txt", content=123
        ) is False
        assert tool.validate_parameters(
            file_path="", content="Hello"
        ) is False
    
    def test_write_file_success(self):
        """Test successfully writing a file."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = WriteFileTool(base_path=tmpdir)
            result = tool.execute(file_path="test.txt", content="Hello, World!")
            
            assert result["success"] is True
            assert "test.txt" in result["file_path"]
            assert result["bytes_written"] == len("Hello, World!")
            
            # Verify file was created
            test_file = Path(tmpdir) / "test.txt"
            assert test_file.exists()
            assert test_file.read_text() == "Hello, World!"
    
    def test_write_file_creates_directories(self):
        """Test that writing to nested path creates directories."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = WriteFileTool(base_path=tmpdir)
            result = tool.execute(
                file_path="subdir/nested/file.txt", content="Content"
            )
            
            assert result["success"] is True
            test_file = Path(tmpdir) / "subdir" / "nested" / "file.txt"
            assert test_file.exists()
            assert test_file.read_text() == "Content"
    
    def test_write_file_absolute_path(self):
        """Test writing file with absolute path."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = WriteFileTool(base_path=tmpdir)
            test_file = Path(tmpdir) / "test.txt"
            
            result = tool.execute(file_path=str(test_file), content="Content")
            assert result["success"] is True
            assert test_file.read_text() == "Content"
    
    def test_write_file_outside_sandbox_raises_error(self):
        """Test that writing file outside sandbox raises ValueError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = WriteFileTool(base_path=tmpdir)
            with tempfile.TemporaryDirectory() as other_dir:
                other_file = Path(other_dir) / "test.txt"
                
                with pytest.raises(ValueError, match="outside sandbox"):
                    tool.execute(file_path=str(other_file), content="Content")
    
    def test_write_file_path_traversal_raises_error(self):
        """Test that path traversal attempts are blocked."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = WriteFileTool(base_path=tmpdir)
            with pytest.raises(ValueError, match="outside sandbox"):
                tool.execute(file_path="../../etc/passwd", content="hack")


class TestListFilesTool:
    """Test cases for ListFilesTool."""
    
    def test_initialization(self):
        """Test tool initialization."""
        tool = ListFilesTool(base_path="/sandbox")
        assert tool.name == "list_files"
        assert tool.base_path == Path("/sandbox").resolve()
    
    def test_validate_parameters_valid(self):
        """Test parameter validation with valid input."""
        tool = ListFilesTool()
        assert tool.validate_parameters(directory_path="subdir") is True
        assert tool.validate_parameters() is True  # directory_path is optional
    
    def test_validate_parameters_invalid_type(self):
        """Test parameter validation with invalid type."""
        tool = ListFilesTool()
        assert tool.validate_parameters(directory_path=123) is False
    
    def test_list_files_success(self):
        """Test successfully listing files."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            
            # Create some files and directories
            (Path(tmpdir) / "file1.txt").write_text("content")
            (Path(tmpdir) / "file2.txt").write_text("content")
            (Path(tmpdir) / "subdir").mkdir()
            
            files = tool.execute()
            assert isinstance(files, list)
            assert "file1.txt" in files
            assert "file2.txt" in files
            assert "subdir" in files
    
    def test_list_files_specific_directory(self):
        """Test listing files in a specific directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            
            subdir = Path(tmpdir) / "subdir"
            subdir.mkdir()
            (subdir / "file.txt").write_text("content")
            
            files = tool.execute(directory_path="subdir")
            assert "file.txt" in files
            assert len(files) == 1
    
    def test_list_files_empty_directory(self):
        """Test listing files in empty directory."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            empty_dir = Path(tmpdir) / "empty"
            empty_dir.mkdir()
            
            files = tool.execute(directory_path="empty")
            assert files == []
    
    def test_list_files_not_found(self):
        """Test listing non-existent directory raises FileNotFoundError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            with pytest.raises(FileNotFoundError):
                tool.execute(directory_path="nonexistent")
    
    def test_list_files_file_not_directory(self):
        """Test listing a file raises ValueError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            (Path(tmpdir) / "file.txt").write_text("content")
            
            with pytest.raises(ValueError, match="not a directory"):
                tool.execute(directory_path="file.txt")
    
    def test_list_files_outside_sandbox_raises_error(self):
        """Test that listing directory outside sandbox raises ValueError."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            with tempfile.TemporaryDirectory() as other_dir:
                with pytest.raises(ValueError, match="outside sandbox"):
                    tool.execute(directory_path=str(other_dir))
    
    def test_list_files_path_traversal_raises_error(self):
        """Test that path traversal attempts are blocked."""
        with tempfile.TemporaryDirectory() as tmpdir:
            tool = ListFilesTool(base_path=tmpdir)
            with pytest.raises(ValueError, match="outside sandbox"):
                tool.execute(directory_path="../../etc")
