"""Configuration classes for Docker container management."""

from dataclasses import dataclass, field
from typing import Dict, List, Optional, Union


@dataclass
class ResourceLimits:
    """Resource limits for Docker containers.
    
    Attributes:
        memory: Memory limit (e.g., "512m", "1g", "2GB")
        cpus: CPU limit as float or string (e.g., 1.0, "1.5", "2")
        pids_limit: Maximum number of processes
        ulimits: List of ulimit dictionaries (e.g., [{"Name": "nofile", "Soft": 1024, "Hard": 2048}])
    """
    memory: Optional[str] = None  # e.g., "512m", "1g"
    cpus: Optional[Union[float, str]] = None  # e.g., 1.0, "1.5"
    pids_limit: Optional[int] = None
    ulimits: Optional[List[Dict[str, int]]] = None
    
    def __post_init__(self):
        """Validate resource limits after initialization."""
        if self.memory is not None:
            self._validate_memory(self.memory)
        if self.cpus is not None:
            self._validate_cpus(self.cpus)
        if self.pids_limit is not None and self.pids_limit < 1:
            raise ValueError("pids_limit must be positive")
        if self.ulimits is not None:
            self._validate_ulimits(self.ulimits)
    
    def _validate_memory(self, memory: str) -> None:
        """Validate memory limit format.
        
        Args:
            memory: Memory limit string
            
        Raises:
            ValueError: If memory format is invalid
        """
        if not isinstance(memory, str):
            raise ValueError(f"Memory limit must be a string, got {type(memory)}")
        
        memory_lower = memory.lower().strip()
        if not memory_lower:
            raise ValueError("Memory limit cannot be empty")
        
        # Check format: number followed by unit (m, g, mb, gb, etc.)
        # Remove unit and check if remaining is numeric
        units = ['b', 'k', 'm', 'g', 't', 'kb', 'mb', 'gb', 'tb']
        for unit in units:
            if memory_lower.endswith(unit):
                value = memory_lower[:-len(unit)]
                try:
                    float(value)
                    return
                except ValueError:
                    pass
        
        # If no unit found, check if entire string is numeric (bytes)
        try:
            int(memory_lower)
            return
        except ValueError:
            pass
        
        raise ValueError(f"Invalid memory format: {memory}. Expected format: '512m', '1g', '2GB', etc.")
    
    def _validate_cpus(self, cpus: Union[float, str]) -> None:
        """Validate CPU limit format.
        
        Args:
            cpus: CPU limit as float or string
            
        Raises:
            ValueError: If CPU format is invalid
        """
        if isinstance(cpus, (int, float)):
            if cpus <= 0:
                raise ValueError("CPU limit must be positive")
            return
        
        if isinstance(cpus, str):
            try:
                cpu_value = float(cpus.strip())
                if cpu_value <= 0:
                    raise ValueError("CPU limit must be positive")
                return
            except ValueError:
                raise ValueError(f"Invalid CPU format: {cpus}. Expected number or numeric string")
        
        raise ValueError(f"CPU limit must be float or string, got {type(cpus)}")
    
    def _validate_ulimits(self, ulimits: List[Dict[str, int]]) -> None:
        """Validate ulimits format.
        
        Args:
            ulimits: List of ulimit dictionaries
            
        Raises:
            ValueError: If ulimits format is invalid
        """
        if not isinstance(ulimits, list):
            raise ValueError(f"ulimits must be a list, got {type(ulimits)}")
        
        for ulimit in ulimits:
            if not isinstance(ulimit, dict):
                raise ValueError(f"Each ulimit must be a dict, got {type(ulimit)}")
            
            # Docker ulimits typically have "Name", "Soft", "Hard" keys
            # But we'll be flexible and just check it's a dict
            if not ulimit:
                raise ValueError("ulimit dict cannot be empty")


@dataclass
class ContainerConfig:
    """Configuration for Docker containers.
    
    Attributes:
        base_image: Base Docker image to use (default: "python:3.11-slim")
        resource_limits: Resource limits for the container
        network_mode: Network mode ("none", "bridge", "host")
        read_only: Whether root filesystem should be read-only
        tmpfs: List of tmpfs mount points
        environment_vars: Environment variables to set
        volumes: Volume mappings (host_path -> container_path config)
        working_dir: Working directory inside container
        user: User to run as (e.g., "sandbox:1000")
        cap_drop: List of capabilities to drop
        cap_add: List of capabilities to add
        security_opt: List of security options
    """
    base_image: str = "python:3.11-slim"
    resource_limits: ResourceLimits = field(default_factory=ResourceLimits)
    network_mode: str = "none"  # "none" | "bridge" | "host"
    read_only: bool = True
    tmpfs: List[str] = field(default_factory=lambda: ["/tmp"])
    environment_vars: Dict[str, str] = field(default_factory=dict)
    volumes: Dict[str, Dict[str, str]] = field(default_factory=dict)
    working_dir: str = "/workspace"
    user: Optional[str] = None  # Run as non-root user
    cap_drop: List[str] = field(default_factory=lambda: ["ALL"])
    cap_add: List[str] = field(default_factory=list)
    security_opt: List[str] = field(default_factory=lambda: ["no-new-privileges:true"])
    
    def __post_init__(self):
        """Validate container configuration after initialization."""
        if not self.base_image:
            raise ValueError("base_image cannot be empty")
        
        self._validate_network_mode(self.network_mode)
        self._validate_working_dir(self.working_dir)
        self._validate_tmpfs(self.tmpfs)
        self._validate_capabilities()
    
    def _validate_network_mode(self, network_mode: str) -> None:
        """Validate network mode.
        
        Args:
            network_mode: Network mode string
            
        Raises:
            ValueError: If network mode is invalid
        """
        valid_modes = ["none", "bridge", "host"]
        if network_mode not in valid_modes:
            raise ValueError(
                f"Invalid network_mode: {network_mode}. "
                f"Must be one of: {', '.join(valid_modes)}"
            )
    
    def _validate_working_dir(self, working_dir: str) -> None:
        """Validate working directory path.
        
        Args:
            working_dir: Working directory path
            
        Raises:
            ValueError: If working directory is invalid
        """
        if not working_dir:
            raise ValueError("working_dir cannot be empty")
        
        if not working_dir.startswith("/"):
            raise ValueError(f"working_dir must be an absolute path, got: {working_dir}")
    
    def _validate_tmpfs(self, tmpfs: List[str]) -> None:
        """Validate tmpfs mount points.
        
        Args:
            tmpfs: List of tmpfs mount points
            
        Raises:
            ValueError: If tmpfs paths are invalid
        """
        if not isinstance(tmpfs, list):
            raise ValueError(f"tmpfs must be a list, got {type(tmpfs)}")
        
        for path in tmpfs:
            if not isinstance(path, str):
                raise ValueError(f"tmpfs paths must be strings, got {type(path)}")
            if not path.startswith("/"):
                raise ValueError(f"tmpfs paths must be absolute, got: {path}")
    
    def _validate_capabilities(self) -> None:
        """Validate capability settings.
        
        Raises:
            ValueError: If capabilities are invalid
        """
        if not isinstance(self.cap_drop, list):
            raise ValueError(f"cap_drop must be a list, got {type(self.cap_drop)}")
        
        if not isinstance(self.cap_add, list):
            raise ValueError(f"cap_add must be a list, got {type(self.cap_add)}")
        
        # Check that all capability strings are non-empty
        for cap in self.cap_drop:
            if not isinstance(cap, str) or not cap.strip():
                raise ValueError(f"Invalid capability in cap_drop: {cap}")
        
        for cap in self.cap_add:
            if not isinstance(cap, str) or not cap.strip():
                raise ValueError(f"Invalid capability in cap_add: {cap}")
    
    def to_docker_dict(self) -> Dict[str, any]:
        """Convert configuration to Docker API format.
        
        Returns:
            Dictionary suitable for Docker API calls
        """
        config = {
            "image": self.base_image,
            "working_dir": self.working_dir,
            "network_mode": self.network_mode,
            "read_only": self.read_only,
            "environment": self.environment_vars,
            "volumes": self.volumes,
            "tmpfs": self.tmpfs,
            "cap_drop": self.cap_drop,
            "cap_add": self.cap_add,
            "security_opt": self.security_opt,
        }
        
        # Add resource limits if specified
        if self.resource_limits.memory:
            config["mem_limit"] = self.resource_limits.memory
        
        if self.resource_limits.cpus is not None:
            # Convert CPU limit to Docker format
            if isinstance(self.resource_limits.cpus, str):
                cpu_value = float(self.resource_limits.cpus)
            else:
                cpu_value = float(self.resource_limits.cpus)
            
            # Docker uses cpu_quota and cpu_period for CPU limits
            # cpu_quota = cpu_value * cpu_period (where cpu_period is typically 100000)
            config["cpu_quota"] = int(cpu_value * 100000)
            config["cpu_period"] = 100000
        
        if self.resource_limits.pids_limit:
            config["pids_limit"] = self.resource_limits.pids_limit
        
        if self.resource_limits.ulimits:
            config["ulimits"] = self.resource_limits.ulimits
        
        # Add user if specified
        if self.user:
            config["user"] = self.user
        
        return config
