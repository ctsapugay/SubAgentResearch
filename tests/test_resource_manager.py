"""Tests for ResourceManager class."""

import pytest
from unittest.mock import Mock, MagicMock, patch
import time

from src.sandbox.resource_manager import ResourceManager
from src.sandbox.container_config import ContainerConfig, ResourceLimits


class TestResourceManager:
    """Tests for ResourceManager class."""
    
    def test_init_with_docker_client(self):
        """Test initialization with provided Docker client."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        assert manager.docker_client == mock_client
        assert manager.default_config is not None
        assert isinstance(manager.default_config, ContainerConfig)
    
    def test_init_with_custom_config(self):
        """Test initialization with custom container config."""
        mock_client = MagicMock()
        custom_config = ContainerConfig(
            resource_limits=ResourceLimits(memory="1g", cpus=2.0)
        )
        manager = ResourceManager(
            docker_client=mock_client,
            default_config=custom_config
        )
        
        assert manager.default_config == custom_config
    
    def test_init_without_docker_client(self):
        """Test initialization without Docker client (requires docker module)."""
        with patch('src.sandbox.resource_manager.DOCKER_AVAILABLE', True):
            with patch('src.sandbox.resource_manager.docker') as mock_docker_module:
                mock_client = MagicMock()
                mock_docker_module.from_env.return_value = mock_client
                
                manager = ResourceManager()
                
                assert manager.docker_client == mock_client
                mock_docker_module.from_env.assert_called_once()
    
    def test_init_docker_not_available(self):
        """Test initialization fails when Docker is not available."""
        with patch('src.sandbox.resource_manager.DOCKER_AVAILABLE', False):
            with pytest.raises(RuntimeError, match="Docker SDK not available"):
                ResourceManager()
    
    def test_get_container_stats_success(self):
        """Test successful retrieval of container stats."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock Docker stats response
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {
                    "total_usage": 1000000000,
                    "percpu_usage": [500000000, 500000000]
                },
                "system_cpu_usage": 2000000000
            },
            "precpu_stats": {
                "cpu_usage": {
                    "total_usage": 500000000,
                    "percpu_usage": [250000000, 250000000]
                },
                "system_cpu_usage": 1000000000
            },
            "memory_stats": {
                "usage": 100 * 1024 * 1024,  # 100 MB
                "limit": 512 * 1024 * 1024   # 512 MB limit
            },
            "networks": {
                "eth0": {
                    "rx_bytes": 1000,
                    "tx_bytes": 2000
                }
            },
            "pids_stats": {
                "current": 5
            }
        }
        
        mock_container.stats.return_value = mock_stats
        mock_client.containers.get.return_value = mock_container
        
        manager = ResourceManager(docker_client=mock_client)
        stats = manager.get_container_stats("test-container-id")
        
        assert "cpu_percent" in stats
        assert "memory_usage" in stats
        assert "memory_limit" in stats
        assert "memory_percent" in stats
        assert "network_rx" in stats
        assert "network_tx" in stats
        assert "pids" in stats
        assert "timestamp" in stats
        
        assert stats["memory_usage"] == 100 * 1024 * 1024
        assert stats["memory_limit"] == 512 * 1024 * 1024
        assert stats["pids"] == 5
        assert stats["network_rx"] == 1000
        assert stats["network_tx"] == 2000
    
    def test_get_container_stats_not_found(self):
        """Test get_container_stats raises NotFound for non-existent container."""
        mock_client = MagicMock()
        
        # Create a mock NotFound exception
        class MockNotFound(Exception):
            pass
        
        mock_client.containers.get.side_effect = MockNotFound("Container not found")
        
        manager = ResourceManager(docker_client=mock_client)
        
        # Patch NotFound in the resource_manager module
        with patch('src.sandbox.resource_manager.NotFound', MockNotFound):
            with pytest.raises(MockNotFound):
                manager.get_container_stats("non-existent")
    
    def test_get_container_stats_invalid_id(self):
        """Test get_container_stats raises ValueError for invalid container ID."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        with pytest.raises(ValueError, match="container_id cannot be empty"):
            manager.get_container_stats("")
        
        with pytest.raises(ValueError, match="container_id cannot be empty"):
            manager.get_container_stats("   ")
    
    def test_parse_memory_limit(self):
        """Test memory limit parsing."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        # Test various formats
        assert manager._parse_memory_limit("512m") == 512 * 1024 * 1024
        assert manager._parse_memory_limit("1g") == 1024 * 1024 * 1024
        assert manager._parse_memory_limit("2GB") == 2 * 1024 * 1024 * 1024
        assert manager._parse_memory_limit("1024") == 1024
        assert manager._parse_memory_limit("") == 0
    
    def test_enforce_limits_no_violations(self):
        """Test enforce_limits when container is within limits."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing low usage
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 100000000, "percpu_usage": [50000000]},
                "system_cpu_usage": 1000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 50000000, "percpu_usage": [25000000]},
                "system_cpu_usage": 500000000
            },
            "memory_stats": {"usage": 100 * 1024 * 1024, "limit": 512 * 1024 * 1024},
            "networks": {},
            "pids_stats": {"current": 5}
        }
        
        mock_container.stats.return_value = mock_stats
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=1.0, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        result = manager.enforce_limits("test-container-id")
        
        assert result["exceeded"] is False
        assert len(result["violations"]) == 0
        assert result["action_taken"] == "none"
        assert "stats" in result
    
    def test_enforce_limits_cpu_violation(self):
        """Test enforce_limits detects CPU limit violation."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing high CPU usage
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 2000000000, "percpu_usage": [1000000000]},
                "system_cpu_usage": 2000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 1000000000, "percpu_usage": [500000000]},
                "system_cpu_usage": 1000000000
            },
            "memory_stats": {"usage": 100 * 1024 * 1024, "limit": 512 * 1024 * 1024},
            "networks": {},
            "pids_stats": {"current": 5}
        }
        
        mock_container.stats.return_value = mock_stats
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=0.5, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        result = manager.enforce_limits("test-container-id", action_on_exceed="log")
        
        assert result["exceeded"] is True
        assert len(result["violations"]) > 0
        assert any("CPU" in v for v in result["violations"])
        assert result["action_taken"] == "logged"
    
    def test_enforce_limits_memory_violation(self):
        """Test enforce_limits detects memory limit violation."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing high memory usage
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 100000000, "percpu_usage": [50000000]},
                "system_cpu_usage": 1000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 50000000, "percpu_usage": [25000000]},
                "system_cpu_usage": 500000000
            },
            "memory_stats": {
                "usage": 600 * 1024 * 1024,  # 600 MB
                "limit": 512 * 1024 * 1024    # 512 MB limit
            },
            "networks": {},
            "pids_stats": {"current": 5}
        }
        
        mock_container.stats.return_value = mock_stats
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=1.0, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        result = manager.enforce_limits("test-container-id", action_on_exceed="log")
        
        assert result["exceeded"] is True
        assert len(result["violations"]) > 0
        assert any("Memory" in v for v in result["violations"])
    
    def test_enforce_limits_pid_violation(self):
        """Test enforce_limits detects PID limit violation."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing high PID count
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 100000000, "percpu_usage": [50000000]},
                "system_cpu_usage": 1000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 50000000, "percpu_usage": [25000000]},
                "system_cpu_usage": 500000000
            },
            "memory_stats": {"usage": 100 * 1024 * 1024, "limit": 512 * 1024 * 1024},
            "networks": {},
            "pids_stats": {"current": 150}  # Exceeds limit of 100
        }
        
        mock_container.stats.return_value = mock_stats
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=1.0, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        result = manager.enforce_limits("test-container-id", action_on_exceed="log")
        
        assert result["exceeded"] is True
        assert len(result["violations"]) > 0
        assert any("Process count" in v for v in result["violations"])
    
    def test_enforce_limits_action_stop(self):
        """Test enforce_limits stops container when action is 'stop'."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing violation
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 2000000000, "percpu_usage": [1000000000]},
                "system_cpu_usage": 2000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 1000000000, "percpu_usage": [500000000]},
                "system_cpu_usage": 1000000000
            },
            "memory_stats": {"usage": 100 * 1024 * 1024, "limit": 512 * 1024 * 1024},
            "networks": {},
            "pids_stats": {"current": 5}
        }
        
        mock_container.stats.return_value = mock_stats
        mock_container.stop.return_value = None
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=0.5, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        result = manager.enforce_limits("test-container-id", action_on_exceed="stop")
        
        assert result["exceeded"] is True
        assert result["action_taken"] == "stopped"
        mock_container.stop.assert_called_once_with(timeout=10)
    
    def test_enforce_limits_action_kill(self):
        """Test enforce_limits kills container when action is 'kill'."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing violation
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 2000000000, "percpu_usage": [1000000000]},
                "system_cpu_usage": 2000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 1000000000, "percpu_usage": [500000000]},
                "system_cpu_usage": 1000000000
            },
            "memory_stats": {"usage": 100 * 1024 * 1024, "limit": 512 * 1024 * 1024},
            "networks": {},
            "pids_stats": {"current": 5}
        }
        
        mock_container.stats.return_value = mock_stats
        mock_container.kill.return_value = None
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=0.5, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        result = manager.enforce_limits("test-container-id", action_on_exceed="kill")
        
        assert result["exceeded"] is True
        assert result["action_taken"] == "killed"
        mock_container.kill.assert_called_once()
    
    def test_enforce_limits_invalid_action(self):
        """Test enforce_limits raises ValueError for invalid action."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        with pytest.raises(ValueError, match="action_on_exceed must be one of"):
            manager.enforce_limits("test-container-id", action_on_exceed="invalid")
    
    def test_enforce_limits_tracks_violations(self):
        """Test enforce_limits tracks violations over time."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        # Mock stats showing violation
        mock_stats = {
            "cpu_stats": {
                "cpu_usage": {"total_usage": 2000000000, "percpu_usage": [1000000000]},
                "system_cpu_usage": 2000000000
            },
            "precpu_stats": {
                "cpu_usage": {"total_usage": 1000000000, "percpu_usage": [500000000]},
                "system_cpu_usage": 1000000000
            },
            "memory_stats": {"usage": 100 * 1024 * 1024, "limit": 512 * 1024 * 1024},
            "networks": {},
            "pids_stats": {"current": 5}
        }
        
        mock_container.stats.return_value = mock_stats
        mock_client.containers.get.return_value = mock_container
        
        config = ContainerConfig(
            resource_limits=ResourceLimits(memory="512m", cpus=0.5, pids_limit=100)
        )
        manager = ResourceManager(docker_client=mock_client, default_config=config)
        
        # First violation
        result1 = manager.enforce_limits("test-container-id", action_on_exceed="log")
        assert result1["exceeded"] is True
        assert "test-container-id" in manager.get_exceeded_containers()
        
        # Second violation
        result2 = manager.enforce_limits("test-container-id", action_on_exceed="log")
        assert result2["exceeded"] is True
        
        violation_info = manager.get_exceeded_containers()["test-container-id"]
        assert violation_info["exceeded_count"] == 2
    
    def test_cleanup_exceeded_containers_by_duration(self):
        """Test cleanup_exceeded_containers cleans up containers exceeding duration."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        mock_client.containers.get.return_value = mock_container
        
        manager = ResourceManager(docker_client=mock_client)
        
        # Manually add a container that exceeded limits long ago
        container_id = "test-container-id"
        manager._exceeded_containers[container_id] = {
            "first_exceeded": time.time() - 400,  # 400 seconds ago
            "exceeded_count": 5
        }
        
        cleaned = manager.cleanup_exceeded_containers(
            exceeded_duration=300,  # 5 minutes
            action="stop"
        )
        
        assert container_id in cleaned
        assert container_id not in manager.get_exceeded_containers()
        mock_container.stop.assert_called_once_with(timeout=10)
    
    def test_cleanup_exceeded_containers_by_count(self):
        """Test cleanup_exceeded_containers cleans up containers exceeding count."""
        mock_client = MagicMock()
        mock_container = MagicMock()
        
        mock_client.containers.get.return_value = mock_container
        
        manager = ResourceManager(docker_client=mock_client)
        
        # Manually add a container with many violations
        container_id = "test-container-id"
        manager._exceeded_containers[container_id] = {
            "first_exceeded": time.time() - 100,  # 100 seconds ago
            "exceeded_count": 15  # Exceeds max of 10
        }
        
        cleaned = manager.cleanup_exceeded_containers(
            max_exceeded_count=10,
            action="kill"
        )
        
        assert container_id in cleaned
        assert container_id not in manager.get_exceeded_containers()
        mock_container.kill.assert_called_once()
    
    def test_cleanup_exceeded_containers_not_found(self):
        """Test cleanup_exceeded_containers handles missing containers gracefully."""
        mock_client = MagicMock()
        
        # Create a mock NotFound exception
        class MockNotFound(Exception):
            pass
        
        mock_client.containers.get.side_effect = MockNotFound("Container not found")
        
        manager = ResourceManager(docker_client=mock_client)
        
        container_id = "test-container-id"
        manager._exceeded_containers[container_id] = {
            "first_exceeded": time.time() - 400,
            "exceeded_count": 5
        }
        
        # Patch NotFound in the resource_manager module
        with patch('src.sandbox.resource_manager.NotFound', MockNotFound):
            cleaned = manager.cleanup_exceeded_containers(
                exceeded_duration=300,
                action="stop"
            )
        
        # Container should be removed from tracking even if not found
        assert container_id not in manager.get_exceeded_containers()
        # But not in cleaned list since it wasn't actually cleaned
        assert container_id not in cleaned
    
    def test_cleanup_exceeded_containers_invalid_action(self):
        """Test cleanup_exceeded_containers raises ValueError for invalid action."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        with pytest.raises(ValueError, match="action must be 'stop' or 'kill'"):
            manager.cleanup_exceeded_containers(action="invalid")
    
    def test_get_exceeded_containers(self):
        """Test get_exceeded_containers returns tracking information."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        # Add some tracking info
        manager._exceeded_containers["container1"] = {
            "first_exceeded": time.time(),
            "exceeded_count": 3
        }
        
        exceeded = manager.get_exceeded_containers()
        
        assert "container1" in exceeded
        assert exceeded["container1"]["exceeded_count"] == 3
        assert "first_exceeded" in exceeded["container1"]
    
    def test_reset_tracking_specific_container(self):
        """Test reset_tracking resets specific container."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        manager._exceeded_containers["container1"] = {"first_exceeded": time.time(), "exceeded_count": 1}
        manager._exceeded_containers["container2"] = {"first_exceeded": time.time(), "exceeded_count": 2}
        
        manager.reset_tracking("container1")
        
        assert "container1" not in manager.get_exceeded_containers()
        assert "container2" in manager.get_exceeded_containers()
    
    def test_reset_tracking_all(self):
        """Test reset_tracking resets all containers."""
        mock_client = MagicMock()
        manager = ResourceManager(docker_client=mock_client)
        
        manager._exceeded_containers["container1"] = {"first_exceeded": time.time(), "exceeded_count": 1}
        manager._exceeded_containers["container2"] = {"first_exceeded": time.time(), "exceeded_count": 2}
        
        manager.reset_tracking()
        
        assert len(manager.get_exceeded_containers()) == 0
