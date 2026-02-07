"""Resource management for Docker containers.

This module provides resource monitoring, limit enforcement, and cleanup
policies for Docker containers used in sandbox isolation.
"""

import logging
import time
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

from src.sandbox.container_config import ContainerConfig, ResourceLimits

logger = logging.getLogger(__name__)


class ResourceManager:
    """Manages resource monitoring and limit enforcement for Docker containers.
    
    This class provides functionality to:
    - Monitor container resource usage (CPU, memory, network, PIDs)
    - Enforce resource limits
    - Clean up containers that exceed limits
    """
    
    def __init__(
        self,
        docker_client: Optional[Any] = None,
        default_config: Optional[ContainerConfig] = None
    ):
        """Initialize resource manager.
        
        Args:
            docker_client: Docker client instance. If None, will attempt to
                create one using docker.from_env(). Must be None if docker is
                not available.
            default_config: Default container configuration for limit comparison.
                If None, uses default ContainerConfig.
        
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
        
        self.default_config = default_config or ContainerConfig()
        
        # Track containers that have exceeded limits
        # Format: {container_id: {"first_exceeded": timestamp, "exceeded_count": int}}
        self._exceeded_containers: Dict[str, Dict[str, Any]] = {}
        
        logger.info("ResourceManager initialized")
    
    def get_container_stats(self, container_id: str) -> Dict[str, Any]:
        """Get current resource usage statistics for a container.
        
        This method retrieves real-time resource usage statistics from Docker
        for the specified container. The stats are collected from Docker's
        stats API which provides CPU, memory, network, and process information.
        
        Args:
            container_id: Container ID to get stats for
        
        Returns:
            Dictionary with resource statistics:
                - cpu_percent: float - CPU usage percentage (0-100)
                - memory_usage: int - Memory usage in bytes
                - memory_limit: int - Memory limit in bytes (0 if unlimited)
                - memory_percent: float - Memory usage percentage (0-100)
                - network_rx: int - Network bytes received
                - network_tx: int - Network bytes transmitted
                - pids: int - Number of processes/threads
                - timestamp: float - Unix timestamp when stats were collected
        
        Raises:
            ValueError: If container_id is invalid
            docker.errors.NotFound: If container doesn't exist
            docker.errors.APIError: If stats retrieval fails
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        try:
            container = self.docker_client.containers.get(container_id)
            
            # Get stats (Docker returns a generator, get one sample)
            stats_generator = container.stats(stream=False, decode=True)
            stats = stats_generator if isinstance(stats_generator, dict) else next(stats_generator)
            
            # Extract CPU stats
            cpu_stats = stats.get("cpu_stats", {})
            precpu_stats = stats.get("precpu_stats", {})
            
            # Calculate CPU percentage
            cpu_percent = 0.0
            if cpu_stats and precpu_stats:
                cpu_delta = (
                    cpu_stats.get("cpu_usage", {}).get("total_usage", 0) -
                    precpu_stats.get("cpu_usage", {}).get("total_usage", 0)
                )
                system_delta = (
                    cpu_stats.get("system_cpu_usage", 0) -
                    precpu_stats.get("system_cpu_usage", 0)
                )
                
                if system_delta > 0 and cpu_delta > 0:
                    # Get number of CPUs
                    num_cpus = len(cpu_stats.get("cpu_usage", {}).get("percpu_usage", []))
                    if num_cpus == 0:
                        num_cpus = 1  # Fallback
                    
                    cpu_percent = (cpu_delta / system_delta) * num_cpus * 100.0
                    cpu_percent = max(0.0, min(100.0, cpu_percent))  # Clamp to 0-100
            
            # Extract memory stats
            memory_stats = stats.get("memory_stats", {})
            memory_usage = memory_stats.get("usage", 0)
            memory_limit = memory_stats.get("limit", 0)
            memory_percent = 0.0
            if memory_limit > 0:
                memory_percent = (memory_usage / memory_limit) * 100.0
            
            # Extract network stats
            networks = stats.get("networks", {})
            network_rx = 0
            network_tx = 0
            for network_stats in networks.values():
                network_rx += network_stats.get("rx_bytes", 0)
                network_tx += network_stats.get("tx_bytes", 0)
            
            # Extract PID stats
            pids = stats.get("pids_stats", {}).get("current", 0)
            
            result = {
                "cpu_percent": round(cpu_percent, 2),
                "memory_usage": memory_usage,
                "memory_limit": memory_limit,
                "memory_percent": round(memory_percent, 2),
                "network_rx": network_rx,
                "network_tx": network_tx,
                "pids": pids,
                "timestamp": time.time()
            }
            
            logger.debug(f"Retrieved stats for container {container_id}: CPU={cpu_percent}%, Memory={memory_percent}%")
            
            return result
            
        except NotFound as e:
            logger.error(f"Container {container_id} not found")
            raise NotFound(f"Container {container_id} not found") from e
        except APIError as e:
            logger.error(f"Failed to get stats for container {container_id}: {e}")
            raise APIError(f"Failed to get container stats: {e}") from e
    
    def _parse_memory_limit(self, memory_limit: str) -> int:
        """Parse memory limit string to bytes.
        
        Args:
            memory_limit: Memory limit string (e.g., "512m", "1g", "2GB")
        
        Returns:
            Memory limit in bytes
        """
        if not memory_limit:
            return 0
        
        memory_lower = memory_limit.lower().strip()
        
        # Extract number and unit
        units = {
            'b': 1,
            'k': 1024,
            'kb': 1024,
            'm': 1024 * 1024,
            'mb': 1024 * 1024,
            'g': 1024 * 1024 * 1024,
            'gb': 1024 * 1024 * 1024,
            't': 1024 * 1024 * 1024 * 1024,
            'tb': 1024 * 1024 * 1024 * 1024,
        }
        
        for unit, multiplier in units.items():
            if memory_lower.endswith(unit):
                value_str = memory_lower[:-len(unit)]
                try:
                    value = float(value_str)
                    return int(value * multiplier)
                except ValueError:
                    pass
        
        # Try parsing as bytes (no unit)
        try:
            return int(memory_lower)
        except ValueError:
            return 0
    
    def enforce_limits(
        self,
        container_id: str,
        config: Optional[ContainerConfig] = None,
        action_on_exceed: str = "log"
    ) -> Dict[str, Any]:
        """Check if container exceeds resource limits and take action.
        
        This method compares the current resource usage of a container against
        its configured limits. If limits are exceeded, it can take various
        actions based on the action_on_exceed parameter.
        
        Args:
            container_id: Container ID to check
            config: Container configuration with limits. If None, uses default_config
            action_on_exceed: Action to take when limits are exceeded:
                - "log": Only log the violation (default)
                - "warn": Log warning and track violation
                - "stop": Stop the container
                - "kill": Kill the container immediately
        
        Returns:
            Dictionary with enforcement results:
                - exceeded: bool - Whether any limits were exceeded
                - violations: List[str] - List of violated limits
                - action_taken: str - Action that was taken
                - stats: Dict[str, Any] - Current container stats
        
        Raises:
            ValueError: If container_id is invalid or action_on_exceed is invalid
            docker.errors.NotFound: If container doesn't exist
            docker.errors.APIError: If enforcement check fails
        """
        if not container_id or not container_id.strip():
            raise ValueError("container_id cannot be empty")
        
        valid_actions = ["log", "warn", "stop", "kill"]
        if action_on_exceed not in valid_actions:
            raise ValueError(
                f"action_on_exceed must be one of {valid_actions}, got '{action_on_exceed}'"
            )
        
        config = config or self.default_config
        limits = config.resource_limits
        
        # Get current stats
        stats = self.get_container_stats(container_id)
        violations = []
        
        # Check CPU limit
        if limits.cpus is not None:
            cpu_limit = float(limits.cpus) * 100.0  # Convert to percentage
            if stats["cpu_percent"] > cpu_limit:
                violations.append(f"CPU usage {stats['cpu_percent']}% exceeds limit {cpu_limit}%")
        
        # Check memory limit
        if limits.memory:
            memory_limit_bytes = self._parse_memory_limit(limits.memory)
            if memory_limit_bytes > 0 and stats["memory_usage"] > memory_limit_bytes:
                violations.append(
                    f"Memory usage {stats['memory_usage']} bytes exceeds limit {memory_limit_bytes} bytes"
                )
            # Also check percentage (more reliable if limit is set)
            if stats["memory_limit"] > 0 and stats["memory_percent"] > 95.0:
                violations.append(
                    f"Memory usage {stats['memory_percent']}% exceeds 95% threshold"
                )
        
        # Check PID limit
        if limits.pids_limit and stats["pids"] > limits.pids_limit:
            violations.append(
                f"Process count {stats['pids']} exceeds limit {limits.pids_limit}"
            )
        
        exceeded = len(violations) > 0
        action_taken = "none"
        
        if exceeded:
            # Track violation
            if container_id not in self._exceeded_containers:
                self._exceeded_containers[container_id] = {
                    "first_exceeded": time.time(),
                    "exceeded_count": 0
                }
            
            self._exceeded_containers[container_id]["exceeded_count"] += 1
            
            # Take action based on action_on_exceed
            if action_on_exceed == "log":
                logger.info(
                    f"Container {container_id} exceeded limits: {', '.join(violations)}"
                )
                action_taken = "logged"
            
            elif action_on_exceed == "warn":
                logger.warning(
                    f"Container {container_id} exceeded limits: {', '.join(violations)}"
                )
                action_taken = "warned"
            
            elif action_on_exceed == "stop":
                try:
                    container = self.docker_client.containers.get(container_id)
                    container.stop(timeout=10)
                    logger.warning(
                        f"Stopped container {container_id} due to limit violations: "
                        f"{', '.join(violations)}"
                    )
                    action_taken = "stopped"
                except Exception as e:
                    logger.error(f"Failed to stop container {container_id}: {e}")
                    action_taken = "stop_failed"
            
            elif action_on_exceed == "kill":
                try:
                    container = self.docker_client.containers.get(container_id)
                    container.kill()
                    logger.warning(
                        f"Killed container {container_id} due to limit violations: "
                        f"{', '.join(violations)}"
                    )
                    action_taken = "killed"
                except Exception as e:
                    logger.error(f"Failed to kill container {container_id}: {e}")
                    action_taken = "kill_failed"
        else:
            # Container is within limits, remove from tracking if present
            if container_id in self._exceeded_containers:
                del self._exceeded_containers[container_id]
        
        return {
            "exceeded": exceeded,
            "violations": violations,
            "action_taken": action_taken,
            "stats": stats
        }
    
    def cleanup_exceeded_containers(
        self,
        exceeded_duration: int = 300,
        max_exceeded_count: int = 10,
        action: str = "stop"
    ) -> List[str]:
        """Find and cleanup containers that have exceeded limits for extended periods.
        
        This method identifies containers that have been exceeding limits for
        a specified duration or have exceeded limits multiple times, and takes
        cleanup action on them.
        
        Args:
            exceeded_duration: Minimum seconds a container must have exceeded
                limits before cleanup (default: 300 = 5 minutes)
            max_exceeded_count: Maximum number of times a container can exceed
                limits before cleanup (default: 10)
            action: Action to take ("stop" or "kill")
        
        Returns:
            List of container IDs that were cleaned up
        
        Raises:
            ValueError: If action is invalid
        """
        if action not in ("stop", "kill"):
            raise ValueError(f"action must be 'stop' or 'kill', got '{action}'")
        
        current_time = time.time()
        containers_to_cleanup = []
        
        # Find containers that meet cleanup criteria
        for container_id, violation_info in list(self._exceeded_containers.items()):
            first_exceeded = violation_info.get("first_exceeded", current_time)
            exceeded_count = violation_info.get("exceeded_count", 0)
            
            duration_exceeded = current_time - first_exceeded
            
            should_cleanup = False
            reason = ""
            
            if duration_exceeded >= exceeded_duration:
                should_cleanup = True
                reason = f"exceeded limits for {duration_exceeded:.0f} seconds"
            
            if exceeded_count >= max_exceeded_count:
                should_cleanup = True
                reason = f"exceeded limits {exceeded_count} times"
            
            if should_cleanup:
                containers_to_cleanup.append((container_id, reason))
        
        # Take cleanup action
        cleaned_containers = []
        for container_id, reason in containers_to_cleanup:
            try:
                container = self.docker_client.containers.get(container_id)
                
                if action == "stop":
                    container.stop(timeout=10)
                    logger.info(
                        f"Stopped container {container_id} due to cleanup policy: {reason}"
                    )
                elif action == "kill":
                    container.kill()
                    logger.info(
                        f"Killed container {container_id} due to cleanup policy: {reason}"
                    )
                
                # Remove from tracking
                if container_id in self._exceeded_containers:
                    del self._exceeded_containers[container_id]
                
                cleaned_containers.append(container_id)
                
            except NotFound:
                # Container already removed, remove from tracking
                if container_id in self._exceeded_containers:
                    del self._exceeded_containers[container_id]
                logger.debug(f"Container {container_id} not found (already removed)")
            except Exception as e:
                logger.error(f"Failed to cleanup container {container_id}: {e}")
        
        if cleaned_containers:
            logger.info(f"Cleaned up {len(cleaned_containers)} container(s) due to limit violations")
        
        return cleaned_containers
    
    def get_exceeded_containers(self) -> Dict[str, Dict[str, Any]]:
        """Get information about containers currently exceeding limits.
        
        Returns:
            Dictionary mapping container_id to violation information:
                - first_exceeded: timestamp when limits were first exceeded
                - exceeded_count: number of times limits were exceeded
        """
        return self._exceeded_containers.copy()
    
    def reset_tracking(self, container_id: Optional[str] = None) -> None:
        """Reset tracking for exceeded containers.
        
        Args:
            container_id: Container ID to reset. If None, resets all tracking.
        """
        if container_id:
            if container_id in self._exceeded_containers:
                del self._exceeded_containers[container_id]
        else:
            self._exceeded_containers.clear()
        
        logger.debug(f"Reset tracking for {'all containers' if container_id is None else container_id}")
