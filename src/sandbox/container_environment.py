"""Container environment builder for creating Docker-based sandbox environments."""

import json
import logging
import shutil
from pathlib import Path
from typing import Any, Dict, Optional

try:
    import docker
    from docker.errors import DockerException, APIError
    DOCKER_AVAILABLE = True
except ImportError:
    DOCKER_AVAILABLE = False
    docker = None
    DockerException = Exception
    APIError = Exception

from src.sandbox.container_config import ContainerConfig
from src.sandbox.container import ContainerManager
from src.sandbox.docker_image_builder import DockerImageBuilder
from src.skill_parser.skill_definition import SkillDefinition

logger = logging.getLogger(__name__)


class ContainerEnvironmentBuilder:
    """Builds container-based sandbox environments.
    
    This class orchestrates the creation of Docker containers for skills by:
    1. Building Docker images from skill requirements
    2. Creating and starting containers
    3. Setting up workspace directories
    4. Saving metadata
    
    It integrates DockerImageBuilder and ContainerManager to provide a
    complete container environment setup.
    """
    
    def __init__(
        self,
        docker_client: Optional[Any] = None,
        base_path: str = "./sandboxes"
    ):
        """Initialize container environment builder.
        
        Args:
            docker_client: Docker client instance. If None, will attempt to
                create one using docker.from_env(). Must be None if docker is
                not available.
            base_path: Base directory for sandbox workspaces
        
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
        
        self.base_path = Path(base_path)
        self.base_path.mkdir(parents=True, exist_ok=True)
        
        # Initialize sub-components
        self.image_builder = DockerImageBuilder(self.docker_client)
        self.container_manager = ContainerManager(self.docker_client, str(self.base_path))
        
        logger.info(f"ContainerEnvironmentBuilder initialized with base_path: {self.base_path}")
    
    def create_environment(
        self,
        skill: SkillDefinition,
        sandbox_id: str,
        config: Optional[ContainerConfig] = None
    ) -> Dict[str, Any]:
        """Create a container environment for a skill.
        
        Args:
            skill: Skill definition containing requirements
            sandbox_id: Unique identifier for this sandbox
            config: Container configuration (defaults to ContainerConfig())
        
        Returns:
            Dictionary with keys:
                - sandbox_id: str
                - container_id: str
                - image_tag: str
                - workspace_path: str
        
        Raises:
            ValueError: If sandbox_id is invalid or sandbox already exists
            docker.errors.BuildError: If image build fails
            docker.errors.APIError: If container creation fails
        """
        if not sandbox_id or not sandbox_id.strip():
            raise ValueError("sandbox_id cannot be empty")
        
        # Use default config if not provided
        if config is None:
            config = ContainerConfig()
        
        # Check if sandbox already exists
        sandbox_path = self.base_path / sandbox_id
        if sandbox_path.exists():
            raise ValueError(f"Sandbox {sandbox_id} already exists")
        
        try:
            # Generate image tag from skill requirements
            image_tag = self.image_builder._generate_image_tag(
                skill,
                config.base_image
            )
            
            # Build Docker image if it doesn't exist
            if not self.image_builder._image_exists(image_tag):
                logger.info(f"Building image {image_tag} for skill {skill.name}")
                self.image_builder.build_image_from_skill(
                    skill,
                    base_image=config.base_image,
                    tag=image_tag
                )
            else:
                logger.info(f"Using existing image {image_tag}")
            
            # Create container
            logger.info(f"Creating container for sandbox {sandbox_id}")
            container_id = self.container_manager.create_container(
                skill=skill,
                sandbox_id=sandbox_id,
                image_tag=image_tag,
                config=config
            )
            
            # Start container
            logger.info(f"Starting container {container_id}")
            self.container_manager.start_container(container_id)
            
            # Create workspace directory structure
            workspace_path = sandbox_path / "workspace"
            logs_path = sandbox_path / "logs"
            workspace_path.mkdir(parents=True, exist_ok=True)
            logs_path.mkdir(parents=True, exist_ok=True)
            
            # Save metadata
            self._save_metadata(
                sandbox_path=sandbox_path,
                skill=skill,
                container_id=container_id,
                image_tag=image_tag,
                config=config
            )
            
            logger.info(
                f"Successfully created container environment for sandbox {sandbox_id}"
            )
            
            return {
                "sandbox_id": sandbox_id,
                "container_id": container_id,
                "image_tag": image_tag,
                "workspace_path": str(workspace_path)
            }
            
        except Exception as e:
            # Clean up on failure
            logger.error(f"Failed to create container environment: {e}")
            try:
                self.cleanup(sandbox_id)
            except Exception:
                pass  # Ignore cleanup errors during failure
            raise RuntimeError(f"Failed to create container environment: {e}") from e
    
    def cleanup(self, sandbox_id: str, remove_image: bool = False) -> bool:
        """Clean up container environment.
        
        Args:
            sandbox_id: Unique identifier for the sandbox to clean up
            remove_image: If True, remove the Docker image (default: False)
        
        Returns:
            True if sandbox was cleaned up, False if it didn't exist
        """
        if not sandbox_id or not sandbox_id.strip():
            return False
        
        sandbox_path = self.base_path / sandbox_id
        
        if not sandbox_path.exists():
            logger.warning(f"Sandbox {sandbox_id} does not exist")
            return False
        
        try:
            # Load metadata to get container_id and image_tag
            metadata_path = sandbox_path / "metadata.json"
            container_id = None
            image_tag = None
            
            if metadata_path.exists():
                try:
                    with open(metadata_path, "r", encoding="utf-8") as f:
                        metadata = json.load(f)
                        container_id = metadata.get("container_id")
                        image_tag = metadata.get("image_tag")
                except Exception as e:
                    logger.warning(f"Failed to load metadata: {e}")
            
            # Stop and remove container
            if container_id:
                try:
                    # Try to stop container (might already be stopped)
                    try:
                        self.container_manager.stop_container(container_id)
                    except Exception:
                        pass  # Container might already be stopped
                    
                    # Remove container
                    self.container_manager.remove_container(container_id, force=True)
                    logger.info(f"Removed container {container_id}")
                except Exception as e:
                    logger.warning(f"Failed to remove container {container_id}: {e}")
            
            # Remove image if requested
            if remove_image and image_tag:
                try:
                    self.docker_client.images.remove(image_tag, force=True)
                    logger.info(f"Removed image {image_tag}")
                except Exception as e:
                    logger.warning(f"Failed to remove image {image_tag}: {e}")
            
            # Remove workspace directory
            if sandbox_path.exists():
                shutil.rmtree(sandbox_path)
                logger.info(f"Removed sandbox directory {sandbox_path}")
            
            return True
            
        except Exception as e:
            logger.error(f"Failed to cleanup sandbox {sandbox_id}: {e}")
            return False
    
    def _save_metadata(
        self,
        sandbox_path: Path,
        skill: SkillDefinition,
        container_id: str,
        image_tag: str,
        config: ContainerConfig
    ) -> None:
        """Save skill and container metadata as JSON.
        
        Args:
            sandbox_path: Path to the sandbox directory
            skill: The skill definition
            container_id: Docker container ID
            image_tag: Docker image tag
            config: Container configuration
        """
        metadata = {
            "sandbox_id": sandbox_path.name,
            "container_id": container_id,
            "image_tag": image_tag,
            "skill_name": skill.name,
            "skill_description": skill.description,
            "system_prompt": skill.system_prompt,
            "tools": [
                {
                    "name": tool.name,
                    "tool_type": tool.tool_type.value,
                    "description": tool.description,
                    "parameters": tool.parameters,
                }
                for tool in skill.tools
            ],
            "environment_requirements": skill.environment_requirements,
            "metadata": skill.metadata,
            "container_config": {
                "base_image": config.base_image,
                "network_mode": config.network_mode,
                "read_only": config.read_only,
                "working_dir": config.working_dir,
                "resource_limits": {
                    "memory": config.resource_limits.memory,
                    "cpus": config.resource_limits.cpus,
                    "pids_limit": config.resource_limits.pids_limit,
                } if config.resource_limits else {},
            },
            "workspace_path": str(sandbox_path / "workspace"),
            "logs_path": str(sandbox_path / "logs"),
        }
        
        metadata_path = sandbox_path / "metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)
        
        logger.debug(f"Saved metadata to {metadata_path}")
