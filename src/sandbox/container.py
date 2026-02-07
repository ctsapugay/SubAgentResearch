"""Docker container management for sandbox isolation."""

import logging
from pathlib import Path
from typing import Any, Dict, List, Optional

try:
    import docker
    from docker.errors import DockerException, NotFound, APIError
    DOCKER_AVAILABLE = True
except ImportError:
    DOCKER_AVAILABLE = False
    docker = None
    DockerException = Exception
    NotFound = Exception
    APIError = Exception

from src.sandbox.container_config import ContainerConfig
from src.skill_parser.skill_definition import SkillDefinition

logger = logging.getLogger(__name__)


class ContainerManager:
    """Manages Docker container lifecycle for sandbox isolation.
    
    This class handles creating, starting, stopping, and executing commands
    within Docker containers. It provides a clean interface for container
    management with proper error handling and resource management.
    """
    
    def __init__(
        self,
        docker_client: Optional[Any] = None,
        base_path: str = "./sandboxes"
    ):
        """Initialize container manager.
        
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
        
        logger.info(f"ContainerManager initialized with base_path: {self.base_path}")
    
    def create_container(
        self,
        skill: SkillDefinition,
        sandbox_id: str,
        image_tag: str,
        config: ContainerConfig
    ) -> str:
        """Create a Docker container for a sandbox.
        
        Args:
            skill: Skill definition (used for metadata)
            sandbox_id: Unique identifier for the sandbox
            image_tag: Docker image tag to use
            config: Container configuration
        
        Returns:
            Container ID
        
        Raises:
            ValueError: If sandbox_id or image_tag is invalid
            docker.errors.NotFound: If image doesn't exist
            docker.errors.APIError: If container creation fails
        """
        if not sandbox_id or not sandbox_id.strip():
            raise ValueError("sandbox_id cannot be empty")
        
        if not image_tag or not image_tag.strip():
            raise ValueError("image_tag cannot be empty")
        
        # Create workspace directory
        workspace_path = self.base_path / sandbox_id / "workspace"
        workspace_path.mkdir(parents=True, exist_ok=True)
        
        # Create volume mapping
        volumes = {
            str(workspace_path.absolute()): {
                "bind": config.working_dir,
                "mode": "rw"
            }
        }
        
        # Merge with any additional volumes from config
        volumes.update(config.volumes)
        
        # Prepare container creation parameters
        container_params = {
            "image": image_tag,
            "name": f"sandbox-{sandbox_id}",
            "working_dir": config.working_dir,
            "volumes": volumes,
            "network_mode": config.network_mode,
            "read_only": config.read_only,
            "tmpfs": {path: "" for path in config.tmpfs},  # Docker expects dict
            "environment": config.environment_vars,
            "detach": True,
            "auto_remove": False,  # We'll manage cleanup
        }
        
        # Add resource limits
        if config.resource_limits.memory:
            container_params["mem_limit"] = config.resource_limits.memory
        
        if config.resource_limits.cpus is not None:
            cpu_value = float(config.resource_limits.cpus)
            container_params["cpu_quota"] = int(cpu_value * 100000)
            container_params["cpu_period"] = 100000
        
        if config.resource_limits.pids_limit:
            container_params["pids_limit"] = config.resource_limits.pids_limit
        
        if config.resource_limits.ulimits:
            container_params["ulimits"] = config.resource_limits.ulimits
        
        # Add security options
        if config.user:
            container_params["user"] = config.user
        
        if config.cap_drop:
            container_params["cap_drop"] = config.cap_drop
        
        if config.cap_add:
            container_params["cap_add"] = config.cap_add
        
        if config.security_opt:
            container_params["security_opt"] = config.security_opt
        
        try:
            container = self.docker_client.containers.create(**container_params)
            logger.info(
                f"Created container {container.id} for sandbox {sandbox_id} "
                f"using image {image_tag}"
            )
            return container.id
        except NotFound as e:
            logger.error(f"Image {image_tag} not found")
            raise NotFound(f"Image {image_tag} not found. Build the image first.") from e
        except APIError as e:
            logger.error(f"Failed to create container: {e}")
            raise APIError(f"Failed to create container: {e}") from e
    
    def start_container(self, container_id: str) -> None:
        """Start a container.
        
        Args:
            container_id: Container ID to start
        
        Raises:
            ValueError: If container_id is invalid
            docker.errors.NotFound: If container doesn't exist
            docker.errors.APIError: If container start fails
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        try:
            container = self.docker_client.containers.get(container_id)
            container.start()
            logger.info(f"Started container {container_id}")
        except NotFound as e:
            logger.error(f"Container {container_id} not found")
            raise NotFound(f"Container {container_id} not found") from e
        except APIError as e:
            logger.error(f"Failed to start container {container_id}: {e}")
            raise APIError(f"Failed to start container: {e}") from e
    
    def stop_container(self, container_id: str, timeout: int = 10) -> None:
        """Stop a container.
        
        Args:
            container_id: Container ID to stop
            timeout: Timeout in seconds before killing the container
        
        Raises:
            ValueError: If container_id is invalid
            docker.errors.NotFound: If container doesn't exist
            docker.errors.APIError: If container stop fails
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        try:
            container = self.docker_client.containers.get(container_id)
            container.stop(timeout=timeout)
            logger.info(f"Stopped container {container_id}")
        except NotFound as e:
            logger.error(f"Container {container_id} not found")
            raise NotFound(f"Container {container_id} not found") from e
        except APIError as e:
            logger.error(f"Failed to stop container {container_id}: {e}")
            raise APIError(f"Failed to stop container: {e}") from e
    
    def remove_container(self, container_id: str, force: bool = False) -> None:
        """Remove a container.
        
        Args:
            container_id: Container ID to remove
            force: If True, force remove even if running
        
        Raises:
            ValueError: If container_id is invalid
            docker.errors.NotFound: If container doesn't exist
            docker.errors.APIError: If container removal fails
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        try:
            container = self.docker_client.containers.get(container_id)
            container.remove(force=force)
            logger.info(f"Removed container {container_id}")
        except NotFound:
            # Container already removed, that's fine
            logger.warning(f"Container {container_id} not found (already removed?)")
        except APIError as e:
            logger.error(f"Failed to remove container {container_id}: {e}")
            raise APIError(f"Failed to remove container: {e}") from e
    
    def execute_in_container(
        self,
        container_id: str,
        command: List[str],
        timeout: int = 30
    ) -> Dict[str, Any]:
        """Execute a command in container.
        
        This method executes a command within a running container and returns
        the result. The container must be running before calling this method.
        
        Args:
            container_id: Container ID to execute in
            command: Command to execute as a list of strings (e.g., ["python", "-c", "print('hello')"])
            timeout: Timeout in seconds
        
        Returns:
            Dictionary with keys:
                - exit_code: int - Exit code of the command
                - stdout: str - Standard output
                - stderr: str - Standard error
                - error: Optional[str] - Error message if execution failed
        
        Raises:
            ValueError: If container_id is invalid or command is empty
            docker.errors.NotFound: If container doesn't exist
            docker.errors.APIError: If execution fails
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        if not command or not isinstance(command, list):
            raise ValueError("command must be a non-empty list")
        
        if not all(isinstance(arg, str) for arg in command):
            raise ValueError("All command arguments must be strings")
        
        try:
            container = self.docker_client.containers.get(container_id)
            
            # Check if container is running
            container.reload()
            if container.status != "running":
                raise APIError(
                    f"Container {container_id} is not running (status: {container.status})"
                )
            
            # Execute command
            exec_result = container.exec_run(
                cmd=command,
                stdout=True,
                stderr=True,
                timeout=timeout
            )
            
            exit_code = exec_result.exit_code
            output = exec_result.output
            
            # Decode output (Docker returns bytes)
            if isinstance(output, bytes):
                # Try to decode, but handle potential encoding issues
                try:
                    decoded_output = output.decode('utf-8')
                except UnicodeDecodeError:
                    decoded_output = output.decode('utf-8', errors='replace')
            else:
                decoded_output = str(output)
            
            # Split stdout and stderr (Docker exec_run combines them)
            # For now, we'll return the combined output as stdout
            # In practice, Docker exec_run doesn't separate them easily
            result = {
                "exit_code": exit_code,
                "stdout": decoded_output,
                "stderr": "",  # Docker exec_run doesn't separate stdout/stderr easily
                "error": None
            }
            
            if exit_code != 0:
                result["error"] = f"Command exited with code {exit_code}"
            
            logger.debug(
                f"Executed command in container {container_id}: "
                f"exit_code={exit_code}"
            )
            
            return result
            
        except NotFound as e:
            logger.error(f"Container {container_id} not found")
            raise NotFound(f"Container {container_id} not found") from e
        except APIError as e:
            logger.error(f"Failed to execute command in container {container_id}: {e}")
            raise APIError(f"Failed to execute command: {e}") from e
    
    def get_container_info(self, container_id: str) -> Dict[str, Any]:
        """Get container information.
        
        Args:
            container_id: Container ID
        
        Returns:
            Dictionary with container information:
                - id: Container ID
                - name: Container name
                - status: Container status (running, stopped, etc.)
                - image: Image tag
                - created: Creation timestamp
                - labels: Container labels
        
        Raises:
            ValueError: If container_id is invalid
            docker.errors.NotFound: If container doesn't exist
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        try:
            container = self.docker_client.containers.get(container_id)
            container.reload()  # Refresh container state
            
            return {
                "id": container.id,
                "name": container.name,
                "status": container.status,
                "image": container.image.tags[0] if container.image.tags else str(container.image.id),
                "created": container.attrs.get("Created", ""),
                "labels": container.labels,
                "working_dir": container.attrs.get("Config", {}).get("WorkingDir", ""),
            }
        except NotFound as e:
            logger.error(f"Container {container_id} not found")
            raise NotFound(f"Container {container_id} not found") from e
    
    def list_containers(
        self,
        sandbox_id: Optional[str] = None,
        all_containers: bool = False
    ) -> List[str]:
        """List containers, optionally filtered by sandbox_id.
        
        Args:
            sandbox_id: If provided, only return containers for this sandbox
            all_containers: If True, include stopped containers
        
        Returns:
            List of container IDs
        """
        try:
            containers = self.docker_client.containers.list(all=all_containers)
            
            if sandbox_id:
                # Filter by sandbox ID (containers are named sandbox-{sandbox_id})
                prefix = f"sandbox-{sandbox_id}"
                filtered = [
                    c.id for c in containers
                    if c.name.startswith(prefix) or c.name == prefix
                ]
                return filtered
            
            # Return all sandbox containers
            return [
                c.id for c in containers
                if c.name.startswith("sandbox-")
            ]
        except Exception as e:
            logger.error(f"Failed to list containers: {e}")
            return []
    
    def cleanup_containers(self, sandbox_id: Optional[str] = None) -> int:
        """Clean up containers.
        
        Args:
            sandbox_id: If provided, only clean up containers for this sandbox.
                If None, clean up all sandbox containers.
        
        Returns:
            Number of containers cleaned up
        """
        containers_to_cleanup = self.list_containers(
            sandbox_id=sandbox_id,
            all_containers=True  # Include stopped containers
        )
        
        cleaned_count = 0
        for container_id in containers_to_cleanup:
            try:
                # Stop if running, then remove
                try:
                    self.stop_container(container_id, timeout=5)
                except (NotFound, APIError):
                    # Container might already be stopped, continue
                    pass
                
                self.remove_container(container_id, force=True)
                cleaned_count += 1
            except Exception as e:
                logger.warning(f"Failed to cleanup container {container_id}: {e}")
        
        logger.info(f"Cleaned up {cleaned_count} container(s)")
        return cleaned_count
