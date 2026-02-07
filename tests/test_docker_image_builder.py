"""Tests for DockerImageBuilder class."""

import pytest
from unittest.mock import Mock, MagicMock, patch, call
from datetime import datetime, timedelta

from src.sandbox.docker_image_builder import DockerImageBuilder
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


class TestDockerImageBuilder:
    """Tests for DockerImageBuilder class."""
    
    def test_init_with_docker_client(self):
        """Test initialization with provided Docker client."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        
        assert builder.docker_client == mock_client
    
    def test_init_without_docker_client(self):
        """Test initialization without Docker client (requires docker module)."""
        with patch('src.sandbox.docker_image_builder.DOCKER_AVAILABLE', True):
            with patch('src.sandbox.docker_image_builder.docker') as mock_docker_module:
                mock_client = MagicMock()
                mock_docker_module.from_env.return_value = mock_client
                
                builder = DockerImageBuilder()
                
                assert builder.docker_client == mock_client
                mock_docker_module.from_env.assert_called_once()
    
    def test_init_docker_not_available(self):
        """Test initialization when docker module is not available."""
        with patch('src.sandbox.docker_image_builder.DOCKER_AVAILABLE', False):
            with pytest.raises(RuntimeError, match="Docker SDK not available"):
                DockerImageBuilder()
    
    def test_init_docker_connection_failure(self):
        """Test initialization when Docker daemon is not available."""
        with patch('src.sandbox.docker_image_builder.DOCKER_AVAILABLE', True):
            with patch('src.sandbox.docker_image_builder.docker') as mock_docker_module:
                mock_docker_module.from_env.side_effect = Exception("Connection refused")
                
                with pytest.raises(RuntimeError, match="Failed to connect to Docker daemon"):
                    DockerImageBuilder()
    
    def test_generate_dockerfile_basic(self):
        """Test Dockerfile generation with basic requirements."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        dockerfile = builder._generate_dockerfile(skill, "python:3.11-slim")
        
        assert "FROM python:3.11-slim" in dockerfile
        assert "WORKDIR /workspace" in dockerfile
        assert "USER sandbox" in dockerfile
        assert "ENV PYTHONUNBUFFERED=1" in dockerfile
        assert "ENV PYTHONPATH=/workspace" in dockerfile
    
    def test_generate_dockerfile_with_packages(self):
        """Test Dockerfile generation with Python packages."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(packages=["requests", "numpy"])
        
        dockerfile = builder._generate_dockerfile(skill, "python:3.11-slim")
        
        assert "pip install --no-cache-dir requests numpy" in dockerfile
    
    def test_generate_dockerfile_with_system_packages(self):
        """Test Dockerfile generation with system packages."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(system_packages=["git", "curl"])
        
        dockerfile = builder._generate_dockerfile(skill, "python:3.11-slim")
        
        assert "apt-get install -y git curl" in dockerfile
        assert "rm -rf /var/lib/apt/lists/*" in dockerfile
    
    def test_generate_dockerfile_with_both_packages(self):
        """Test Dockerfile generation with both Python and system packages."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(
            packages=["requests"],
            system_packages=["git"]
        )
        
        dockerfile = builder._generate_dockerfile(skill, "python:3.11-slim")
        
        assert "apt-get install -y git" in dockerfile
        assert "pip install --no-cache-dir requests" in dockerfile
    
    def test_generate_image_tag(self):
        """Test image tag generation from skill."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(name="Test Skill", packages=["requests"])
        
        tag = builder._generate_image_tag(skill, "python:3.11-slim")
        
        assert tag.startswith("skill-test-skill-")
        assert len(tag) > len("skill-test-skill-")
    
    def test_generate_image_tag_consistent(self):
        """Test that same skill generates same tag."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill1 = create_mock_skill(name="Test", packages=["requests"])
        skill2 = create_mock_skill(name="Test", packages=["requests"])
        
        tag1 = builder._generate_image_tag(skill1, "python:3.11-slim")
        tag2 = builder._generate_image_tag(skill2, "python:3.11-slim")
        
        assert tag1 == tag2
    
    def test_generate_image_tag_different_packages(self):
        """Test that different packages generate different tags."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill1 = create_mock_skill(name="Test", packages=["requests"])
        skill2 = create_mock_skill(name="Test", packages=["numpy"])
        
        tag1 = builder._generate_image_tag(skill1, "python:3.11-slim")
        tag2 = builder._generate_image_tag(skill2, "python:3.11-slim")
        
        assert tag1 != tag2
    
    def test_image_exists_true(self):
        """Test checking if image exists when it does."""
        mock_client = MagicMock()
        mock_image = MagicMock()
        mock_client.images.get.return_value = mock_image
        
        builder = DockerImageBuilder(docker_client=mock_client)
        exists = builder._image_exists("test-image:tag")
        
        assert exists is True
        mock_client.images.get.assert_called_once_with("test-image:tag")
    
    def test_image_exists_false(self):
        """Test checking if image exists when it doesn't."""
        mock_client = MagicMock()
        mock_client.images.get.side_effect = Exception("Image not found")
        
        builder = DockerImageBuilder(docker_client=mock_client)
        exists = builder._image_exists("nonexistent-image:tag")
        
        assert exists is False
    
    def test_build_image_from_skill_success(self):
        """Test successful image building."""
        mock_client = MagicMock()
        mock_image = MagicMock()
        mock_image.id = "test-image-id"
        mock_client.images.get.side_effect = Exception("Image not found")  # Image doesn't exist
        mock_client.images.build.return_value = (mock_image, [{"stream": "Success"}])
        
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(packages=["requests"])
        
        tag = builder.build_image_from_skill(skill, "python:3.11-slim")
        
        assert tag is not None
        assert mock_client.images.build.called
    
    def test_build_image_from_skill_image_exists(self):
        """Test image building when image already exists."""
        mock_client = MagicMock()
        mock_image = MagicMock()
        mock_client.images.get.return_value = mock_image  # Image exists
        
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        tag = builder.build_image_from_skill(skill, "python:3.11-slim")
        
        # Should return tag without building
        assert tag is not None
        assert not mock_client.images.build.called
    
    def test_build_image_from_skill_custom_tag(self):
        """Test image building with custom tag."""
        mock_client = MagicMock()
        mock_client.images.get.side_effect = Exception("Image not found")
        mock_image = MagicMock()
        mock_client.images.build.return_value = (mock_image, [])
        
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        custom_tag = "custom-image:tag"
        tag = builder.build_image_from_skill(skill, "python:3.11-slim", tag=custom_tag)
        
        assert tag == custom_tag
        call_args = mock_client.images.build.call_args
        assert call_args[1]["tag"] == custom_tag
    
    def test_build_image_from_skill_invalid_skill(self):
        """Test image building with invalid skill."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        
        with pytest.raises(ValueError, match="skill cannot be None"):
            builder.build_image_from_skill(None, "python:3.11-slim")
    
    def test_build_image_from_skill_invalid_base_image(self):
        """Test image building with invalid base image."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        with pytest.raises(ValueError, match="base_image cannot be empty"):
            builder.build_image_from_skill(skill, "")
        
        with pytest.raises(ValueError, match="base_image cannot be empty"):
            builder.build_image_from_skill(skill, "   ")
    
    def test_build_image_from_skill_build_error(self):
        """Test image building when build fails."""
        BuildError = type('BuildError', (Exception,), {})
        
        mock_client = MagicMock()
        mock_client.images.get.side_effect = Exception("Image not found")
        mock_client.images.build.side_effect = BuildError("Build failed")
        
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill()
        
        with pytest.raises(Exception, match="Failed to build image"):
            builder.build_image_from_skill(skill, "python:3.11-slim")
    
    def test_requirements_to_string(self):
        """Test requirements to string conversion."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(
            python_version="3.11",
            packages=["requests", "numpy"],
            system_packages=["git"]
        )
        
        req_str = builder._requirements_to_string(skill, "python:3.11-slim")
        
        assert "python:3.11-slim" in req_str
        assert "3.11" in req_str
        assert "requests" in req_str or "numpy" in req_str
        assert "git" in req_str
    
    def test_requirements_to_string_consistent(self):
        """Test that requirements string is consistent for same inputs."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        skill = create_mock_skill(packages=["requests", "numpy"])
        
        req_str1 = builder._requirements_to_string(skill, "python:3.11-slim")
        req_str2 = builder._requirements_to_string(skill, "python:3.11-slim")
        
        assert req_str1 == req_str2
    
    def test_dockerfile_to_fileobj(self):
        """Test Dockerfile to file object conversion."""
        mock_client = MagicMock()
        builder = DockerImageBuilder(docker_client=mock_client)
        
        dockerfile_content = "FROM python:3.11-slim\nWORKDIR /workspace"
        fileobj = builder._dockerfile_to_fileobj(dockerfile_content)
        
        assert fileobj is not None
        content = fileobj.read().decode('utf-8')
        assert "FROM python:3.11-slim" in content
    
    def test_get_image_info_exists(self):
        """Test getting image info when image exists."""
        mock_client = MagicMock()
        mock_image = MagicMock()
        mock_image.id = "test-image-id"
        mock_image.tags = ["test-image:tag"]
        mock_image.attrs = {
            "Created": "2024-01-01T00:00:00Z",
            "Size": 1000000,
            "Architecture": "amd64"
        }
        mock_client.images.get.return_value = mock_image
        
        builder = DockerImageBuilder(docker_client=mock_client)
        info = builder.get_image_info("test-image:tag")
        
        assert info is not None
        assert info["id"] == "test-image-id"
        assert info["tags"] == ["test-image:tag"]
        assert info["size"] == 1000000
    
    def test_get_image_info_not_exists(self):
        """Test getting image info when image doesn't exist."""
        mock_client = MagicMock()
        mock_client.images.get.side_effect = Exception("Image not found")
        
        builder = DockerImageBuilder(docker_client=mock_client)
        info = builder.get_image_info("nonexistent:tag")
        
        assert info is None
    
    def test_list_images(self):
        """Test listing images with prefix."""
        mock_client = MagicMock()
        mock_image1 = MagicMock()
        mock_image1.tags = ["skill-test-abc123", "other-tag"]
        mock_image2 = MagicMock()
        mock_image2.tags = ["skill-test-def456"]
        mock_image3 = MagicMock()
        mock_image3.tags = ["other-image:tag"]
        
        mock_client.images.list.return_value = [
            mock_image1,
            mock_image2,
            mock_image3
        ]
        
        builder = DockerImageBuilder(docker_client=mock_client)
        images = builder.list_images(skill_prefix="skill-")
        
        assert len(images) == 2
        assert "skill-test-abc123" in images
        assert "skill-test-def456" in images
        assert "other-image:tag" not in images
    
    def test_list_images_error_handling(self):
        """Test list_images handles errors gracefully."""
        mock_client = MagicMock()
        mock_client.images.list.side_effect = Exception("Error")
        
        builder = DockerImageBuilder(docker_client=mock_client)
        images = builder.list_images()
        
        assert images == []
    
    def test_cleanup_unused_images(self):
        """Test cleanup of unused images."""
        from datetime import timezone
        mock_client = MagicMock()
        
        # Create mock images with different creation dates (UTC-aware)
        old_date = (datetime.now(timezone.utc) - timedelta(days=10)).isoformat().replace("+00:00", "Z")
        new_date = (datetime.now(timezone.utc) - timedelta(days=1)).isoformat().replace("+00:00", "Z")
        
        mock_image_old = MagicMock()
        mock_image_old.id = "old-image-id"
        mock_image_old.tags = ["old-image:tag"]
        mock_image_old.attrs = {"Created": old_date}
        
        mock_image_new = MagicMock()
        mock_image_new.id = "new-image-id"
        mock_image_new.tags = ["new-image:tag"]
        mock_image_new.attrs = {"Created": new_date}
        
        mock_client.images.list.return_value = [mock_image_old, mock_image_new]
        mock_client.images.remove.return_value = None
        
        builder = DockerImageBuilder(docker_client=mock_client)
        removed_count = builder.cleanup_unused_images(older_than_days=7)
        
        # Only old image should be removed
        assert removed_count == 1
        mock_client.images.remove.assert_called_once_with("old-image-id", force=True)
    
    def test_cleanup_unused_images_keep_tags(self):
        """Test cleanup with keep_tags parameter."""
        from datetime import timezone
        mock_client = MagicMock()
        
        old_date = (datetime.now(timezone.utc) - timedelta(days=10)).isoformat().replace("+00:00", "Z")
        
        mock_image_old = MagicMock()
        mock_image_old.id = "old-image-id"
        mock_image_old.tags = ["keep-me:tag"]
        mock_image_old.attrs = {"Created": old_date}
        
        mock_client.images.list.return_value = [mock_image_old]
        
        builder = DockerImageBuilder(docker_client=mock_client)
        removed_count = builder.cleanup_unused_images(
            older_than_days=7,
            keep_tags=["keep-me:tag"]
        )
        
        # Image should not be removed because it's in keep_tags
        assert removed_count == 0
        assert not mock_client.images.remove.called
    
    def test_cleanup_unused_images_handles_errors(self):
        """Test cleanup handles errors gracefully."""
        from datetime import timezone
        mock_client = MagicMock()
        
        old_date = (datetime.now(timezone.utc) - timedelta(days=10)).isoformat().replace("+00:00", "Z")
        
        mock_image = MagicMock()
        mock_image.id = "old-image-id"
        mock_image.tags = ["old-image:tag"]
        mock_image.attrs = {"Created": old_date}
        
        mock_client.images.list.return_value = [mock_image]
        mock_client.images.remove.side_effect = Exception("Remove failed")
        
        builder = DockerImageBuilder(docker_client=mock_client)
        removed_count = builder.cleanup_unused_images(older_than_days=7)
        
        # Should handle error gracefully
        assert removed_count == 0
