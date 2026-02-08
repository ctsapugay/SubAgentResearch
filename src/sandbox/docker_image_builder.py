"""Docker image builder for creating container images from skill definitions."""

import hashlib
import logging
from datetime import datetime, timedelta
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import docker
    from docker.errors import DockerException, BuildError, APIError
    DOCKER_AVAILABLE = True
except ImportError:
    DOCKER_AVAILABLE = False
    docker = None
    DockerException = Exception
    BuildError = Exception
    APIError = Exception

from src.skill_parser.skill_definition import SkillDefinition

logger = logging.getLogger(__name__)


class DockerImageBuilder:
    """Builds Docker images from skill definitions.
    
    This class generates Dockerfiles dynamically based on skill requirements
    and builds Docker images with caching support. Images are tagged using
    a hash of the skill requirements for efficient caching.
    """
    
    def __init__(self, docker_client: Optional[Any] = None):
        """Initialize Docker image builder.
        
        Args:
            docker_client: Docker client instance. If None, will attempt to
                create one using docker.from_env(). Must be None if docker is
                not available.
        
        Raises:
            RuntimeError: If docker is not available and docker_client is None
            docker.errors.DockerException: If unable to connect to Docker daemon
        """
        if not DOCKER_AVAILABLE and docker_client is None:
            raise RuntimeError(
                "Docker SDK not available. Install with: pip install docker>=6.0.0"
            )
        
        if docker_client is None:
            try:
                self.docker_client = docker.from_env()
            except Exception as e:
                raise RuntimeError(
                    f"Failed to connect to Docker daemon: {e}. "
                    "Make sure Docker is running."
                ) from e
        else:
            self.docker_client = docker_client
        
        logger.info("DockerImageBuilder initialized")
    
    def build_image_from_skill(
        self,
        skill: SkillDefinition,
        base_image: str = "python:3.11-slim",
        tag: Optional[str] = None,
        build_args: Optional[Dict[str, str]] = None
    ) -> str:
        """Build Docker image for a skill.
        
        Args:
            skill: Skill definition containing requirements
            base_image: Base Docker image to use (default: "python:3.11-slim")
            tag: Optional custom tag. If None, generates tag from skill hash
            build_args: Optional build arguments for Dockerfile
        
        Returns:
            Image tag/ID
        
        Raises:
            ValueError: If skill or base_image is invalid
            docker.errors.BuildError: If image build fails
            docker.errors.APIError: If Docker API call fails
        """
        if not skill:
            raise ValueError("skill cannot be None")
        
        if not base_image or not base_image.strip():
            raise ValueError("base_image cannot be empty")
        
        # Generate image tag from skill hash if not provided
        if tag is None:
            tag = self._generate_image_tag(skill, base_image)
        
        # Check if image already exists
        if self._image_exists(tag):
            logger.info(f"Image {tag} already exists, skipping build")
            return tag
        
        # Generate Dockerfile
        dockerfile_content = self._generate_dockerfile(skill, base_image)
        
        # Build image
        logger.info(f"Building image {tag} from skill {skill.name}")
        try:
            image, build_logs = self.docker_client.images.build(
                fileobj=self._dockerfile_to_fileobj(dockerfile_content),
                tag=tag,
                rm=True,  # Remove intermediate containers
                pull=False,  # Don't pull base image if it exists locally
                buildargs=build_args or {}
            )
            
            # Log build output
            for log_entry in build_logs:
                if 'stream' in log_entry:
                    logger.debug(log_entry['stream'].strip())
            
            logger.info(f"Successfully built image {tag}")
            return tag
            
        except BuildError as e:
            logger.error(f"Failed to build image {tag}: {e}")
            raise BuildError(f"Failed to build image: {e}", e.build_log) from e
        except APIError as e:
            logger.error(f"Docker API error while building image {tag}: {e}")
            raise APIError(f"Docker API error: {e}") from e
    
    def _generate_dockerfile(
        self,
        skill: SkillDefinition,
        base_image: str
    ) -> str:
        """Generate Dockerfile content from skill requirements.
        
        Args:
            skill: Skill definition
            base_image: Base Docker image
        
        Returns:
            Dockerfile content as string
        """
        lines = [
            f"FROM {base_image}",
            "",
            "# Set working directory",
            "WORKDIR /workspace",
            "",
            "# Create non-root user",
            "RUN useradd -m -u 1000 sandbox && \\",
            "    chown -R sandbox:sandbox /workspace",
            ""
        ]
        
        # Install system packages if specified
        system_packages = skill.environment_requirements.get("system_packages", [])
        if system_packages:
            packages_str = " ".join(system_packages)
            lines.extend([
                "# Install system packages",
                f"RUN apt-get update && \\",
                f"    apt-get install -y {packages_str} && \\",
                "    rm -rf /var/lib/apt/lists/*",
                ""
            ])
        
        # Install Python packages if specified
        packages = skill.environment_requirements.get("packages", [])
        if packages:
            packages_str = " ".join(packages)
            lines.extend([
                "# Install Python packages",
                f"RUN pip install --no-cache-dir {packages_str}",
                ""
            ])
        
        # Switch to non-root user
        lines.extend([
            "# Switch to non-root user",
            "USER sandbox",
            "",
            "# Set environment variables",
            "ENV PYTHONUNBUFFERED=1",
            "ENV PYTHONPATH=/workspace",
            "",
            "# Keep container alive for exec_run commands",
            'CMD ["sleep", "infinity"]'
        ])
        
        return "\n".join(lines)
    
    def _generate_image_tag(
        self,
        skill: SkillDefinition,
        base_image: str
    ) -> str:
        """Generate image tag from skill requirements hash.
        
        Args:
            skill: Skill definition
            base_image: Base Docker image
        
        Returns:
            Image tag string (format: skill-{hash})
        """
        # Create hash from skill requirements
        requirements_str = self._requirements_to_string(skill, base_image)
        requirements_hash = hashlib.sha256(requirements_str.encode()).hexdigest()[:12]
        
        # Sanitize skill name for tag
        sanitized_name = skill.name.lower().replace(" ", "-").replace("_", "-")
        sanitized_name = "".join(c for c in sanitized_name if c.isalnum() or c == "-")
        
        tag = f"skill-{sanitized_name}-{requirements_hash}"
        return tag
    
    def _requirements_to_string(
        self,
        skill: SkillDefinition,
        base_image: str
    ) -> str:
        """Convert skill requirements to string for hashing.
        
        Args:
            skill: Skill definition
            base_image: Base Docker image
        
        Returns:
            String representation of requirements
        """
        parts = [
            base_image,
            skill.environment_requirements.get("python_version", ""),
        ]
        
        # Add packages (sorted for consistent hashing)
        packages = skill.environment_requirements.get("packages", [])
        if packages:
            parts.append("|".join(sorted(packages)))
        
        # Add system packages (sorted for consistent hashing)
        system_packages = skill.environment_requirements.get("system_packages", [])
        if system_packages:
            parts.append("sys:" + "|".join(sorted(system_packages)))
        
        return "\n".join(parts)
    
    def _dockerfile_to_fileobj(self, dockerfile_content: str):
        """Convert Dockerfile content to file-like object for Docker API.
        
        Args:
            dockerfile_content: Dockerfile content as string
        
        Returns:
            File-like object
        """
        import io
        return io.BytesIO(dockerfile_content.encode('utf-8'))
    
    def _image_exists(self, tag: str) -> bool:
        """Check if Docker image exists locally.
        
        Args:
            tag: Image tag
        
        Returns:
            True if image exists, False otherwise
        """
        try:
            self.docker_client.images.get(tag)
            return True
        except Exception:
            return False
    
    def cleanup_unused_images(
        self,
        older_than_days: int = 7,
        keep_tags: Optional[List[str]] = None
    ) -> int:
        """Remove unused Docker images older than specified days.
        
        Args:
            older_than_days: Remove images older than this many days
            keep_tags: List of image tags to keep (even if old)
        
        Returns:
            Number of images removed
        """
        keep_tags = keep_tags or []
        # Use UTC-aware datetime for comparison
        from datetime import timezone
        cutoff_date = datetime.now(timezone.utc) - timedelta(days=older_than_days)
        
        removed_count = 0
        try:
            images = self.docker_client.images.list(all=True)
            
            for image in images:
                # Skip if tag is in keep list
                image_tags = image.tags or []
                if any(tag in keep_tags for tag in image_tags):
                    continue
                
                # Skip if image is too recent
                created_str = image.attrs.get("Created", "")
                if created_str:
                    try:
                        # Docker timestamp format: "2024-01-01T00:00:00.000000000Z"
                        # Parse as UTC-aware datetime
                        created_date = datetime.fromisoformat(
                            created_str.replace("Z", "+00:00")
                        )
                        # Compare timezone-aware datetimes
                        if created_date > cutoff_date:
                            continue
                    except (ValueError, AttributeError):
                        # If we can't parse date, skip this image
                        continue
                
                # Remove image
                try:
                    self.docker_client.images.remove(image.id, force=True)
                    removed_count += 1
                    logger.info(f"Removed unused image {image.id[:12]}")
                except Exception as e:
                    logger.warning(f"Failed to remove image {image.id[:12]}: {e}")
            
            logger.info(f"Cleaned up {removed_count} unused image(s)")
            return removed_count
            
        except Exception as e:
            logger.error(f"Failed to cleanup unused images: {e}")
            return removed_count
    
    def get_image_info(self, tag: str) -> Optional[Dict[str, any]]:
        """Get information about a Docker image.
        
        Args:
            tag: Image tag
        
        Returns:
            Dictionary with image information, or None if image doesn't exist
        """
        try:
            image = self.docker_client.images.get(tag)
            return {
                "id": image.id,
                "tags": image.tags,
                "created": image.attrs.get("Created", ""),
                "size": image.attrs.get("Size", 0),
                "architecture": image.attrs.get("Architecture", ""),
            }
        except Exception:
            return None
    
    def list_images(self, skill_prefix: str = "skill-") -> List[str]:
        """List all images with a given prefix.
        
        Args:
            skill_prefix: Prefix to filter images (default: "skill-")
        
        Returns:
            List of image tags
        """
        try:
            images = self.docker_client.images.list(all=True)
            tags = []
            for image in images:
                for tag in (image.tags or []):
                    if tag.startswith(skill_prefix):
                        tags.append(tag)
            return tags
        except Exception as e:
            logger.error(f"Failed to list images: {e}")
            return []
