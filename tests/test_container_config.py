"""Tests for container configuration classes."""

import pytest

from src.sandbox.container_config import ContainerConfig, ResourceLimits


class TestResourceLimits:
    """Tests for ResourceLimits class."""
    
    def test_default_resource_limits(self):
        """Test creating ResourceLimits with default values."""
        limits = ResourceLimits()
        assert limits.memory is None
        assert limits.cpus is None
        assert limits.pids_limit is None
        assert limits.ulimits is None
    
    def test_valid_memory_formats(self):
        """Test valid memory limit formats."""
        valid_formats = ["512m", "1g", "2GB", "1024", "512mb", "1.5g"]
        for mem_format in valid_formats:
            limits = ResourceLimits(memory=mem_format)
            assert limits.memory == mem_format
    
    def test_invalid_memory_formats(self):
        """Test invalid memory limit formats."""
        # Test empty string
        with pytest.raises(ValueError, match="Memory limit cannot be empty"):
            ResourceLimits(memory="")
        
        # Test invalid formats (non-numeric strings without units)
        invalid_formats = ["abc", "xyz", "1.5"]  # 1.5 without unit is invalid
        for mem_format in invalid_formats:
            with pytest.raises(ValueError, match="Invalid memory format"):
                ResourceLimits(memory=mem_format)
    
    def test_memory_not_string(self):
        """Test that memory must be a string."""
        with pytest.raises(ValueError, match="Memory limit must be a string"):
            ResourceLimits(memory=512)
    
    def test_valid_cpu_formats(self):
        """Test valid CPU limit formats."""
        valid_cpus = [1.0, 2.5, "1.0", "2.5", "1", 1]
        for cpu in valid_cpus:
            limits = ResourceLimits(cpus=cpu)
            assert limits.cpus == cpu
    
    def test_invalid_cpu_formats(self):
        """Test invalid CPU limit formats."""
        invalid_cpus = [0, -1, -0.5, "abc", ""]
        for cpu in invalid_cpus:
            with pytest.raises(ValueError, match="CPU limit must be positive|Invalid CPU format"):
                ResourceLimits(cpus=cpu)
    
    def test_valid_pids_limit(self):
        """Test valid PID limits."""
        limits = ResourceLimits(pids_limit=100)
        assert limits.pids_limit == 100
    
    def test_invalid_pids_limit(self):
        """Test invalid PID limits."""
        with pytest.raises(ValueError, match="pids_limit must be positive"):
            ResourceLimits(pids_limit=0)
        
        with pytest.raises(ValueError, match="pids_limit must be positive"):
            ResourceLimits(pids_limit=-1)
    
    def test_valid_ulimits(self):
        """Test valid ulimits."""
        ulimits = [
            {"Name": "nofile", "Soft": 1024, "Hard": 2048},
            {"Name": "nproc", "Soft": 100, "Hard": 200}
        ]
        limits = ResourceLimits(ulimits=ulimits)
        assert limits.ulimits == ulimits
    
    def test_invalid_ulimits(self):
        """Test invalid ulimits."""
        with pytest.raises(ValueError, match="ulimits must be a list"):
            ResourceLimits(ulimits="not a list")
        
        with pytest.raises(ValueError, match="Each ulimit must be a dict"):
            ResourceLimits(ulimits=["not a dict"])
        
        with pytest.raises(ValueError, match="ulimit dict cannot be empty"):
            ResourceLimits(ulimits=[{}])
    
    def test_all_limits_together(self):
        """Test setting all limits together."""
        limits = ResourceLimits(
            memory="512m",
            cpus=1.5,
            pids_limit=100,
            ulimits=[{"Name": "nofile", "Soft": 1024, "Hard": 2048}]
        )
        assert limits.memory == "512m"
        assert limits.cpus == 1.5
        assert limits.pids_limit == 100
        assert len(limits.ulimits) == 1


class TestContainerConfig:
    """Tests for ContainerConfig class."""
    
    def test_default_container_config(self):
        """Test creating ContainerConfig with default values."""
        config = ContainerConfig()
        assert config.base_image == "python:3.11-slim"
        assert isinstance(config.resource_limits, ResourceLimits)
        assert config.network_mode == "none"
        assert config.read_only is True
        assert config.tmpfs == ["/tmp"]
        assert config.environment_vars == {}
        assert config.volumes == {}
        assert config.working_dir == "/workspace"
        assert config.user is None
        assert config.cap_drop == ["ALL"]
        assert config.cap_add == []
        assert config.security_opt == ["no-new-privileges:true"]
    
    def test_custom_base_image(self):
        """Test setting custom base image."""
        config = ContainerConfig(base_image="python:3.12-slim")
        assert config.base_image == "python:3.12-slim"
    
    def test_empty_base_image(self):
        """Test that base_image cannot be empty."""
        with pytest.raises(ValueError, match="base_image cannot be empty"):
            ContainerConfig(base_image="")
    
    def test_valid_network_modes(self):
        """Test valid network modes."""
        valid_modes = ["none", "bridge", "host"]
        for mode in valid_modes:
            config = ContainerConfig(network_mode=mode)
            assert config.network_mode == mode
    
    def test_invalid_network_mode(self):
        """Test invalid network mode."""
        with pytest.raises(ValueError, match="Invalid network_mode"):
            ContainerConfig(network_mode="invalid")
    
    def test_read_only_flag(self):
        """Test read_only flag."""
        config = ContainerConfig(read_only=False)
        assert config.read_only is False
    
    def test_custom_working_dir(self):
        """Test custom working directory."""
        config = ContainerConfig(working_dir="/app")
        assert config.working_dir == "/app"
    
    def test_invalid_working_dir(self):
        """Test invalid working directory."""
        with pytest.raises(ValueError, match="working_dir must be an absolute path"):
            ContainerConfig(working_dir="relative/path")
        
        with pytest.raises(ValueError, match="working_dir cannot be empty"):
            ContainerConfig(working_dir="")
    
    def test_custom_tmpfs(self):
        """Test custom tmpfs mounts."""
        tmpfs = ["/tmp", "/var/tmp"]
        config = ContainerConfig(tmpfs=tmpfs)
        assert config.tmpfs == tmpfs
    
    def test_invalid_tmpfs(self):
        """Test invalid tmpfs paths."""
        with pytest.raises(ValueError, match="tmpfs paths must be absolute"):
            ContainerConfig(tmpfs=["relative/path"])
        
        with pytest.raises(ValueError, match="tmpfs paths must be strings"):
            ContainerConfig(tmpfs=[123])
    
    def test_environment_vars(self):
        """Test environment variables."""
        env_vars = {"PYTHONPATH": "/workspace", "DEBUG": "true"}
        config = ContainerConfig(environment_vars=env_vars)
        assert config.environment_vars == env_vars
    
    def test_volumes(self):
        """Test volume mappings."""
        volumes = {
            "/host/path": {"bind": "/container/path", "mode": "rw"}
        }
        config = ContainerConfig(volumes=volumes)
        assert config.volumes == volumes
    
    def test_user(self):
        """Test user setting."""
        config = ContainerConfig(user="sandbox:1000")
        assert config.user == "sandbox:1000"
    
    def test_capabilities(self):
        """Test capability settings."""
        config = ContainerConfig(
            cap_drop=["NET_RAW", "SYS_ADMIN"],
            cap_add=["NET_BIND_SERVICE"]
        )
        assert "NET_RAW" in config.cap_drop
        assert "NET_BIND_SERVICE" in config.cap_add
    
    def test_invalid_capabilities(self):
        """Test invalid capability settings."""
        with pytest.raises(ValueError, match="cap_drop must be a list"):
            ContainerConfig(cap_drop="not a list")
        
        with pytest.raises(ValueError, match="Invalid capability in cap_drop"):
            ContainerConfig(cap_drop=[""])
        
        with pytest.raises(ValueError, match="Invalid capability in cap_add"):
            ContainerConfig(cap_add=[""])
    
    def test_security_opt(self):
        """Test security options."""
        security_opts = ["no-new-privileges:true", "seccomp=unconfined"]
        config = ContainerConfig(security_opt=security_opts)
        assert config.security_opt == security_opts
    
    def test_custom_resource_limits(self):
        """Test custom resource limits."""
        resource_limits = ResourceLimits(memory="1g", cpus=2.0, pids_limit=200)
        config = ContainerConfig(resource_limits=resource_limits)
        assert config.resource_limits.memory == "1g"
        assert config.resource_limits.cpus == 2.0
        assert config.resource_limits.pids_limit == 200
    
    def test_to_docker_dict_basic(self):
        """Test converting config to Docker API format."""
        config = ContainerConfig()
        docker_dict = config.to_docker_dict()
        
        assert docker_dict["image"] == "python:3.11-slim"
        assert docker_dict["working_dir"] == "/workspace"
        assert docker_dict["network_mode"] == "none"
        assert docker_dict["read_only"] is True
        assert docker_dict["tmpfs"] == ["/tmp"]
        assert docker_dict["cap_drop"] == ["ALL"]
        assert docker_dict["security_opt"] == ["no-new-privileges:true"]
    
    def test_to_docker_dict_with_resources(self):
        """Test converting config with resource limits."""
        resource_limits = ResourceLimits(memory="512m", cpus=1.5, pids_limit=100)
        config = ContainerConfig(resource_limits=resource_limits)
        docker_dict = config.to_docker_dict()
        
        assert docker_dict["mem_limit"] == "512m"
        assert docker_dict["cpu_quota"] == 150000  # 1.5 * 100000
        assert docker_dict["cpu_period"] == 100000
        assert docker_dict["pids_limit"] == 100
    
    def test_to_docker_dict_with_user(self):
        """Test converting config with user."""
        config = ContainerConfig(user="sandbox:1000")
        docker_dict = config.to_docker_dict()
        assert docker_dict["user"] == "sandbox:1000"
    
    def test_to_docker_dict_with_ulimits(self):
        """Test converting config with ulimits."""
        ulimits = [{"Name": "nofile", "Soft": 1024, "Hard": 2048}]
        resource_limits = ResourceLimits(ulimits=ulimits)
        config = ContainerConfig(resource_limits=resource_limits)
        docker_dict = config.to_docker_dict()
        assert docker_dict["ulimits"] == ulimits
    
    def test_to_docker_dict_cpu_string(self):
        """Test CPU limit as string."""
        resource_limits = ResourceLimits(cpus="2.5")
        config = ContainerConfig(resource_limits=resource_limits)
        docker_dict = config.to_docker_dict()
        assert docker_dict["cpu_quota"] == 250000  # 2.5 * 100000
    
    def test_complete_config(self):
        """Test a complete configuration."""
        resource_limits = ResourceLimits(
            memory="1g",
            cpus=2.0,
            pids_limit=200
        )
        config = ContainerConfig(
            base_image="python:3.12-slim",
            resource_limits=resource_limits,
            network_mode="bridge",
            read_only=False,
            tmpfs=["/tmp"],
            environment_vars={"DEBUG": "true"},
            volumes={"/host": {"bind": "/container", "mode": "ro"}},
            working_dir="/app",
            user="appuser:1000",
            cap_drop=["ALL"],
            cap_add=["NET_BIND_SERVICE"],
            security_opt=["no-new-privileges:true"]
        )
        
        assert config.base_image == "python:3.12-slim"
        assert config.resource_limits.memory == "1g"
        assert config.network_mode == "bridge"
        assert config.read_only is False
        assert config.user == "appuser:1000"
        
        docker_dict = config.to_docker_dict()
        assert docker_dict["image"] == "python:3.12-slim"
        assert docker_dict["mem_limit"] == "1g"
        assert docker_dict["network_mode"] == "bridge"
        assert docker_dict["read_only"] is False
        assert docker_dict["user"] == "appuser:1000"
