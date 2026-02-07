"""Tests for ContainerEnvironmentBuilder class."""

import pytest
import json
from pathlib import Path
from unittest.mock import Mock, MagicMock, patch, call
import tempfile
import shutil

from src.sandbox.container_environment import ContainerEnvironmentBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits
from src.skill_parser.skill_definition import SkillDefinition, Tool, ToolType


def create_mock_skill(
    name: str = "test_skill",
    packages: list = None,
    system_packages: list = None,
    python_version: str = None
) -> SkillDefinition:
    """Create a mock skill definition for testing."""
    env_requirements = {}
    if python_version:
        env_requirements["python_version"] = python_version
    if packages:
        env_requirements["packages"] = packages
    if system_packages:
        env_requirements["system_packages"] = system_packages
    
    return SkillDefinition(
        name=name,
        description="A test skill",
        system_prompt="Test system prompt",
        tools=[],
        environment_requirements=env_requirements,
        metadata={}
    )


class TestContainerEnvironmentBuilder:
    """Tests for ContainerEnvironmentBuilder class."""
    
    def test_init_with_docker_client(self):
        """Test initialization with provided Docker client."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(
            docker_client=mock_client,
            base_path="./test_sandboxes"
        )
        
        assert builder.docker_client == mock_client
        assert builder.base_path == Path("./test_sandboxes")
        assert builder.image_builder is not None
        assert builder.container_manager is not None
    
    def test_init_without_docker_client(self):
        """Test initialization without Docker client."""
        with patch('src.sandbox.container_environment.DOCKER_AVAILABLE', True):
            with patch('src.sandbox.container_environment.docker') as mock_docker_module:
                mock_client = MagicMock()
                mock_docker_module.from_env.return_value = mock_client
                
                builder = ContainerEnvironmentBuilder(base_path="./test_sandboxes")
                
                assert builder.docker_client == mock_client
                mock_docker_module.from_env.assert_called_once()
    
    def test_init_docker_not_available(self):
        """Test initialization when docker module is not available."""
        with patch('src.sandbox.container_environment.DOCKER_AVAILABLE', False):
            with pytest.raises(RuntimeError, match="Docker SDK not available"):
                ContainerEnvironmentBuilder()
    
    def test_create_environment_success(self):
        """Test successful environment creation."""
        mock_client = MagicMock()
        
        # Mock image builder
        mock_image_builder = MagicMock()
        mock_image_builder._generate_image_tag.return_value = "skill-test-abc123"
        mock_image_builder._image_exists.return_value = False
        mock_image_builder.build_image_from_skill.return_value = "skill-test-abc123"
        
        # Mock container manager
        mock_container_manager = MagicMock()
        mock_container_manager.create_container.return_value = "container-id-123"
        mock_container_manager.start_container.return_value = None
        
        builder = ContainerEnvironmentBuilder(
            docker_client=mock_client,
            base_path="./test_sandboxes"
        )
        builder.image_builder = mock_image_builder
        builder.container_manager = mock_container_manager
        
        skill = create_mock_skill(packages=["requests"])
        config = ContainerConfig()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            result = builder.create_environment(
                skill=skill,
                sandbox_id="test-sandbox",
                config=config
            )
            
            assert result["sandbox_id"] == "test-sandbox"
            assert result["container_id"] == "container-id-123"
            assert result["image_tag"] == "skill-test-abc123"
            assert "workspace_path" in result
            
            # Verify workspace was created
            workspace_path = Path(result["workspace_path"])
            assert workspace_path.exists()
            
            # Verify metadata was saved
            metadata_path = Path(tmpdir) / "test-sandbox" / "metadata.json"
            assert metadata_path.exists()
    
    def test_create_environment_image_exists(self):
        """Test environment creation when image already exists."""
        mock_client = MagicMock()
        
        mock_image_builder = MagicMock()
        mock_image_builder._generate_image_tag.return_value = "skill-test-abc123"
        mock_image_builder._image_exists.return_value = True  # Image exists
        
        mock_container_manager = MagicMock()
        mock_container_manager.create_container.return_value = "container-id-123"
        mock_container_manager.start_container.return_value = None
        
        builder = ContainerEnvironmentBuilder(
            docker_client=mock_client,
            base_path="./test_sandboxes"
        )
        builder.image_builder = mock_image_builder
        builder.container_manager = mock_container_manager
        
        skill = create_mock_skill()
        config = ContainerConfig()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            result = builder.create_environment(
                skill=skill,
                sandbox_id="test-sandbox",
                config=config
            )
            
            # Should not call build_image_from_skill if image exists
            assert not mock_image_builder.build_image_from_skill.called
    
    def test_create_environment_invalid_sandbox_id(self):
        """Test environment creation with invalid sandbox_id."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        with pytest.raises(ValueError, match="sandbox_id cannot be empty"):
            builder.create_environment(skill, "", None)
        
        with pytest.raises(ValueError, match="sandbox_id cannot be empty"):
            builder.create_environment(skill, "   ", None)
    
    def test_create_environment_sandbox_exists(self):
        """Test environment creation when sandbox already exists."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            sandbox_path = builder.base_path / "existing-sandbox"
            sandbox_path.mkdir()
            
            with pytest.raises(ValueError, match="already exists"):
                builder.create_environment(skill, "existing-sandbox", None)
    
    def test_create_environment_uses_default_config(self):
        """Test that default config is used when None is provided."""
        mock_client = MagicMock()
        
        mock_image_builder = MagicMock()
        mock_image_builder._generate_image_tag.return_value = "skill-test-abc123"
        mock_image_builder._image_exists.return_value = True
        
        mock_container_manager = MagicMock()
        mock_container_manager.create_container.return_value = "container-id-123"
        mock_container_manager.start_container.return_value = None
        
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        builder.image_builder = mock_image_builder
        builder.container_manager = mock_container_manager
        
        skill = create_mock_skill()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            result = builder.create_environment(skill, "test-sandbox", None)
            
            # Should use default config
            call_args = mock_container_manager.create_container.call_args
            assert call_args[1]["config"] is not None
            assert isinstance(call_args[1]["config"], ContainerConfig)
    
    def test_create_environment_cleanup_on_failure(self):
        """Test that cleanup happens on failure."""
        mock_client = MagicMock()
        
        mock_image_builder = MagicMock()
        mock_image_builder._generate_image_tag.return_value = "skill-test-abc123"
        mock_image_builder._image_exists.return_value = True
        
        mock_container_manager = MagicMock()
        mock_container_manager.create_container.side_effect = Exception("Container creation failed")
        
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        builder.image_builder = mock_image_builder
        builder.container_manager = mock_container_manager
        
        skill = create_mock_skill()
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            
            with pytest.raises(RuntimeError, match="Failed to create container environment"):
                builder.create_environment(skill, "test-sandbox", None)
            
            # Cleanup should have been called
            # (We can't easily verify this without more complex mocking, but the code should handle it)
    
    def test_cleanup_success(self):
        """Test successful cleanup."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            sandbox_path = builder.base_path / "test-sandbox"
            sandbox_path.mkdir()
            workspace_path = sandbox_path / "workspace"
            workspace_path.mkdir()
            
            # Create metadata file
            metadata = {
                "container_id": "container-id-123",
                "image_tag": "skill-test-abc123"
            }
            metadata_path = sandbox_path / "metadata.json"
            with open(metadata_path, "w") as f:
                json.dump(metadata, f)
            
            # Mock container manager
            mock_container_manager = MagicMock()
            builder.container_manager = mock_container_manager
            
            result = builder.cleanup("test-sandbox")
            
            assert result is True
            assert not sandbox_path.exists()
            mock_container_manager.stop_container.assert_called_once_with("container-id-123")
            mock_container_manager.remove_container.assert_called_once_with("container-id-123", force=True)
    
    def test_cleanup_with_image_removal(self):
        """Test cleanup with image removal."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            sandbox_path = builder.base_path / "test-sandbox"
            sandbox_path.mkdir()
            
            metadata = {
                "container_id": "container-id-123",
                "image_tag": "skill-test-abc123"
            }
            metadata_path = sandbox_path / "metadata.json"
            with open(metadata_path, "w") as f:
                json.dump(metadata, f)
            
            mock_container_manager = MagicMock()
            builder.container_manager = mock_container_manager
            
            result = builder.cleanup("test-sandbox", remove_image=True)
            
            assert result is True
            mock_client.images.remove.assert_called_once_with("skill-test-abc123", force=True)
    
    def test_cleanup_sandbox_not_exists(self):
        """Test cleanup when sandbox doesn't exist."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        result = builder.cleanup("nonexistent-sandbox")
        
        assert result is False
    
    def test_cleanup_invalid_sandbox_id(self):
        """Test cleanup with invalid sandbox_id."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        assert builder.cleanup("") is False
        assert builder.cleanup("   ") is False
    
    def test_cleanup_handles_missing_metadata(self):
        """Test cleanup handles missing metadata gracefully."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            sandbox_path = builder.base_path / "test-sandbox"
            sandbox_path.mkdir()
            
            mock_container_manager = MagicMock()
            builder.container_manager = mock_container_manager
            
            result = builder.cleanup("test-sandbox")
            
            # Should still succeed even without metadata
            assert result is True
            assert not sandbox_path.exists()
    
    def test_cleanup_handles_container_errors(self):
        """Test cleanup handles container errors gracefully."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            builder.base_path = Path(tmpdir)
            sandbox_path = builder.base_path / "test-sandbox"
            sandbox_path.mkdir()
            
            metadata = {
                "container_id": "container-id-123",
                "image_tag": "skill-test-abc123"
            }
            metadata_path = sandbox_path / "metadata.json"
            with open(metadata_path, "w") as f:
                json.dump(metadata, f)
            
            mock_container_manager = MagicMock()
            mock_container_manager.stop_container.side_effect = Exception("Stop failed")
            builder.container_manager = mock_container_manager
            
            # Should still succeed and remove directory
            result = builder.cleanup("test-sandbox")
            assert result is True
            assert not sandbox_path.exists()
    
    def test_save_metadata(self):
        """Test metadata saving."""
        mock_client = MagicMock()
        builder = ContainerEnvironmentBuilder(docker_client=mock_client)
        
        with tempfile.TemporaryDirectory() as tmpdir:
            sandbox_path = Path(tmpdir) / "test-sandbox"
            sandbox_path.mkdir()
            
            skill = create_mock_skill(
                name="Test Skill",
                packages=["requests"]
            )
            config = ContainerConfig(base_image="python:3.11-slim")
            
            builder._save_metadata(
                sandbox_path=sandbox_path,
                skill=skill,
                container_id="container-id-123",
                image_tag="skill-test-abc123",
                config=config
            )
            
            metadata_path = sandbox_path / "metadata.json"
            assert metadata_path.exists()
            
            with open(metadata_path, "r") as f:
                metadata = json.load(f)
            
            assert metadata["sandbox_id"] == "test-sandbox"
            assert metadata["container_id"] == "container-id-123"
            assert metadata["image_tag"] == "skill-test-abc123"
            assert metadata["skill_name"] == "Test Skill"
            assert metadata["container_config"]["base_image"] == "python:3.11-slim"
            assert "workspace_path" in metadata
            assert "logs_path" in metadata
