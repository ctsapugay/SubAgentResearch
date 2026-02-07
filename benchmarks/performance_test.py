#!/usr/bin/env python3
"""
Performance benchmarking script for directory vs container isolation modes.

This script compares:
- Sandbox creation time
- Tool execution overhead
- Resource usage
- Cleanup time

Run this script from the project root directory.
"""

import sys
import time
import statistics
from pathlib import Path
from typing import Dict, List

# Add project root to Python path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src import SandboxBuilder
from src.sandbox.container_config import ContainerConfig, ResourceLimits

try:
    import docker
    DOCKER_AVAILABLE = True
except ImportError:
    DOCKER_AVAILABLE = False


class PerformanceBenchmark:
    """Benchmark performance of different isolation modes."""
    
    def __init__(self, iterations: int = 5):
        """Initialize benchmark.
        
        Args:
            iterations: Number of iterations to run for each test
        """
        self.iterations = iterations
        self.results: Dict[str, List[float]] = {}
        self.skill_path = PROJECT_ROOT / "examples" / "simple_skill.md"
    
    def benchmark_sandbox_creation(self, isolation_mode: str, config=None) -> List[float]:
        """Benchmark sandbox creation time.
        
        Args:
            isolation_mode: "directory" or "container"
            config: ContainerConfig for container mode
        
        Returns:
            List of creation times in seconds
        """
        times = []
        
        for i in range(self.iterations):
            builder = SandboxBuilder(
                isolation_mode=isolation_mode,
                container_config=config
            )
            
            start = time.time()
            try:
                sandbox_id = builder.build_from_skill_file(str(self.skill_path))
                creation_time = time.time() - start
                times.append(creation_time)
                
                # Cleanup immediately
                builder.cleanup(sandbox_id)
            except Exception as e:
                print(f"  ✗ Iteration {i+1} failed: {e}")
                if times:
                    times.append(float('inf'))  # Mark as failed
        
        return times
    
    def benchmark_tool_execution(self, isolation_mode: str, config=None) -> List[float]:
        """Benchmark tool execution time.
        
        Args:
            isolation_mode: "directory" or "container"
            config: ContainerConfig for container mode
        
        Returns:
            List of execution times in seconds
        """
        times = []
        
        # Create sandbox once
        builder = SandboxBuilder(
            isolation_mode=isolation_mode,
            container_config=config
        )
        
        try:
            sandbox_id = builder.build_from_skill_file(str(self.skill_path))
        except Exception as e:
            print(f"  ✗ Failed to create sandbox: {e}")
            return [float('inf')] * self.iterations
        
        # Benchmark tool execution
        for i in range(self.iterations):
            start = time.time()
            try:
                result = builder.execute_in_sandbox(
                    sandbox_id,
                    "write_file",
                    file_path=f"benchmark_{i}.txt",
                    content=f"Benchmark iteration {i}"
                )
                execution_time = time.time() - start
                times.append(execution_time)
            except Exception as e:
                print(f"  ✗ Iteration {i+1} failed: {e}")
                if times:
                    times.append(float('inf'))
        
        # Cleanup
        try:
            builder.cleanup(sandbox_id)
        except Exception:
            pass
        
        return times
    
    def benchmark_cleanup(self, isolation_mode: str, config=None) -> List[float]:
        """Benchmark cleanup time.
        
        Args:
            isolation_mode: "directory" or "container"
            config: ContainerConfig for container mode
        
        Returns:
            List of cleanup times in seconds
        """
        times = []
        
        for i in range(self.iterations):
            builder = SandboxBuilder(
                isolation_mode=isolation_mode,
                container_config=config
            )
            
            try:
                sandbox_id = builder.build_from_skill_file(str(self.skill_path))
            except Exception as e:
                print(f"  ✗ Failed to create sandbox: {e}")
                continue
            
            start = time.time()
            try:
                builder.cleanup(sandbox_id)
                cleanup_time = time.time() - start
                times.append(cleanup_time)
            except Exception as e:
                print(f"  ✗ Cleanup failed: {e}")
        
        return times
    
    def run_benchmark(self, mode: str, config=None):
        """Run all benchmarks for a mode.
        
        Args:
            mode: "directory" or "container"
            config: ContainerConfig for container mode
        """
        print(f"\n{'='*60}")
        print(f"Benchmarking {mode.upper()} Mode")
        print(f"{'='*60}\n")
        
        # Sandbox creation
        print("1. Benchmarking sandbox creation...")
        creation_times = self.benchmark_sandbox_creation(mode, config)
        if creation_times:
            avg = statistics.mean([t for t in creation_times if t != float('inf')])
            median = statistics.median([t for t in creation_times if t != float('inf')])
            print(f"   Average: {avg:.3f}s")
            print(f"   Median: {median:.3f}s")
            self.results[f"{mode}_creation"] = creation_times
        
        # Tool execution
        print("\n2. Benchmarking tool execution...")
        execution_times = self.benchmark_tool_execution(mode, config)
        if execution_times:
            avg = statistics.mean([t for t in execution_times if t != float('inf')])
            median = statistics.median([t for t in execution_times if t != float('inf')])
            print(f"   Average: {avg:.3f}s")
            print(f"   Median: {median:.3f}s")
            self.results[f"{mode}_execution"] = execution_times
        
        # Cleanup
        print("\n3. Benchmarking cleanup...")
        cleanup_times = self.benchmark_cleanup(mode, config)
        if cleanup_times:
            avg = statistics.mean([t for t in cleanup_times if t != float('inf')])
            median = statistics.median([t for t in cleanup_times if t != float('inf')])
            print(f"   Average: {avg:.3f}s")
            print(f"   Median: {median:.3f}s")
            self.results[f"{mode}_cleanup"] = cleanup_times
    
    def print_comparison(self):
        """Print comparison between modes."""
        print(f"\n{'='*60}")
        print("Performance Comparison")
        print(f"{'='*60}\n")
        
        metrics = ["creation", "execution", "cleanup"]
        
        for metric in metrics:
            dir_key = f"directory_{metric}"
            cont_key = f"container_{metric}"
            
            if dir_key in self.results and cont_key in self.results:
                dir_times = [t for t in self.results[dir_key] if t != float('inf')]
                cont_times = [t for t in self.results[cont_key] if t != float('inf')]
                
                if dir_times and cont_times:
                    dir_avg = statistics.mean(dir_times)
                    cont_avg = statistics.mean(cont_times)
                    
                    print(f"{metric.capitalize()}:")
                    print(f"  Directory: {dir_avg:.3f}s")
                    print(f"  Container: {cont_avg:.3f}s")
                    
                    if dir_avg > 0:
                        overhead = ((cont_avg - dir_avg) / dir_avg) * 100
                        print(f"  Overhead: {overhead:+.1f}%")
                    print()


def main():
    """Run performance benchmarks."""
    print("=" * 60)
    print("Performance Benchmark: Directory vs Container Isolation")
    print("=" * 60)
    print(f"\nIterations per test: 5")
    print(f"Skill file: examples/simple_skill.md")
    print()
    
    benchmark = PerformanceBenchmark(iterations=5)
    
    # Benchmark directory mode
    benchmark.run_benchmark("directory")
    
    # Benchmark container mode (if Docker available)
    if DOCKER_AVAILABLE:
        try:
            docker_client = docker.from_env()
            docker_client.ping()
            
            config = ContainerConfig(
                resource_limits=ResourceLimits(memory="512m", cpus=1.0)
            )
            benchmark.run_benchmark("container", config)
        except Exception as e:
            print(f"\n⚠ Docker not available: {e}")
            print("  Skipping container mode benchmarks")
    else:
        print("\n⚠ Docker SDK not installed")
        print("  Install with: pip install docker>=6.0.0")
        print("  Skipping container mode benchmarks")
    
    # Print comparison
    benchmark.print_comparison()
    
    print("=" * 60)
    print("Benchmark completed!")
    print("=" * 60)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("\n\nBenchmark interrupted by user")
    except Exception as e:
        print(f"\n\nError running benchmark: {e}")
        import traceback
        traceback.print_exc()
