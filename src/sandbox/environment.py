"""Environment builder for creating isolated sandbox environments."""

import json
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Optional

from src.skill_parser.skill_definition import SkillDefinition


class EnvironmentBuilder:
    """Builds isolated sandbox environments for skills.
    
    Creates directory structures, sets up Python virtual environments,
    installs required packages, and saves skill metadata.
    """
    
    def __init__(self, base_path: str = "./sandboxes"):
        """Initialize the environment builder.
        
        Args:
            base_path: Base directory where sandboxes will be created
        """
        self.base_path = Path(base_path).resolve()
        self.base_path.mkdir(parents=True, exist_ok=True)
    
    def create_environment(
        self, 
        skill: SkillDefinition, 
        sandbox_id: str
    ) -> Path:
        """Create a sandbox environment for a skill.
        
        Args:
            skill: The skill definition to create environment for
            sandbox_id: Unique identifier for this sandbox
            
        Returns:
            Path to the created sandbox directory
            
        Raises:
            ValueError: If sandbox_id is invalid or environment creation fails
            RuntimeError: If Python environment setup fails
        """
        if not sandbox_id:
            raise ValueError("sandbox_id cannot be empty")
        
        # Create sandbox directory
        sandbox_path = self.base_path / sandbox_id
        if sandbox_path.exists():
            raise ValueError(f"Sandbox {sandbox_id} already exists")
        
        try:
            # Create directory structure
            workspace_path = sandbox_path / "workspace"
            logs_path = sandbox_path / "logs"
            workspace_path.mkdir(parents=True, exist_ok=True)
            logs_path.mkdir(parents=True, exist_ok=True)
            
            # Set up Python virtual environment if needed
            python_version = skill.environment_requirements.get("python_version")
            venv_path = None
            if python_version:
                venv_path = self._setup_python_environment(
                    sandbox_path, 
                    python_version
                )
            
            # Install packages if specified
            packages = skill.environment_requirements.get("packages", [])
            if packages:
                if not venv_path:
                    # Create venv if packages are needed but no version specified
                    venv_path = self._setup_python_environment(
                        sandbox_path,
                        None  # Use system Python
                    )
                self._install_packages(venv_path, packages)
            
            # Save skill metadata
            self._save_metadata(sandbox_path, skill, venv_path)
            
            return sandbox_path
            
        except Exception as e:
            # Clean up on failure
            if sandbox_path.exists():
                shutil.rmtree(sandbox_path)
            raise RuntimeError(f"Failed to create environment: {e}") from e
    
    def cleanup(self, sandbox_id: str) -> bool:
        """Remove a sandbox directory.
        
        Args:
            sandbox_id: Unique identifier for the sandbox to remove
            
        Returns:
            True if sandbox was removed, False if it didn't exist
        """
        sandbox_path = self.base_path / sandbox_id
        if not sandbox_path.exists():
            return False
        
        try:
            shutil.rmtree(sandbox_path)
            return True
        except Exception as e:
            raise RuntimeError(f"Failed to cleanup sandbox {sandbox_id}: {e}") from e
    
    def _setup_python_environment(
        self, 
        sandbox_path: Path, 
        python_version: Optional[str]
    ) -> Path:
        """Set up a Python virtual environment.
        
        Args:
            sandbox_path: Path to the sandbox directory
            python_version: Python version string (e.g., "3.11") or None for system Python
            
        Returns:
            Path to the virtual environment
            
        Raises:
            RuntimeError: If venv creation fails
        """
        venv_path = sandbox_path / "venv"
        
        if venv_path.exists():
            return venv_path
        
        try:
            # Determine Python executable
            if python_version:
                # Try to find specific Python version
                python_exe = f"python{python_version}"
                # Check if it exists
                result = subprocess.run(
                    [python_exe, "--version"],
                    capture_output=True,
                    text=True,
                    timeout=5
                )
                if result.returncode != 0:
                    # Fall back to system Python
                    python_exe = sys.executable
            else:
                python_exe = sys.executable
            
            # Create virtual environment
            result = subprocess.run(
                [python_exe, "-m", "venv", str(venv_path)],
                capture_output=True,
                text=True,
                timeout=30,
                check=True
            )
            
            return venv_path
            
        except subprocess.TimeoutExpired as e:
            raise RuntimeError(
                f"Timeout creating virtual environment: {e}"
            ) from e
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to create virtual environment: {e.stderr}"
            ) from e
        except FileNotFoundError as e:
            raise RuntimeError(
                f"Python executable not found: {e}"
            ) from e
    
    def _install_packages(
        self, 
        venv_path: Path, 
        packages: list
    ) -> None:
        """Install packages in the virtual environment.
        
        Args:
            venv_path: Path to the virtual environment
            packages: List of package names or requirements
            
        Raises:
            RuntimeError: If package installation fails
        """
        if not packages:
            return
        
        # Determine pip executable
        if sys.platform == "win32":
            pip_exe = venv_path / "Scripts" / "pip"
        else:
            pip_exe = venv_path / "bin" / "pip"
        
        if not pip_exe.exists():
            raise RuntimeError(
                f"pip not found in virtual environment at {venv_path}"
            )
        
        try:
            # Install packages
            # If packages is a list of strings, install them directly
            # If it's a single string, treat it as a requirements file path
            if isinstance(packages, str):
                # Single string - could be requirements file or package name
                if Path(packages).exists():
                    # It's a requirements file
                    cmd = [str(pip_exe), "install", "-r", packages]
                else:
                    # It's a package name
                    cmd = [str(pip_exe), "install", packages]
            elif isinstance(packages, list):
                # List of packages
                cmd = [str(pip_exe), "install"] + packages
            else:
                raise ValueError(f"Invalid packages format: {type(packages)}")
            
            result = subprocess.run(
                cmd,
                capture_output=True,
                text=True,
                timeout=300,  # 5 minutes for package installation
                check=True
            )
            
        except subprocess.TimeoutExpired as e:
            raise RuntimeError(
                f"Timeout installing packages: {e}"
            ) from e
        except subprocess.CalledProcessError as e:
            raise RuntimeError(
                f"Failed to install packages: {e.stderr}"
            ) from e
    
    def _save_metadata(
        self, 
        sandbox_path: Path, 
        skill: SkillDefinition,
        venv_path: Optional[Path]
    ) -> None:
        """Save skill metadata as JSON.
        
        Args:
            sandbox_path: Path to the sandbox directory
            skill: The skill definition
            venv_path: Path to virtual environment (if created)
        """
        metadata = {
            "sandbox_id": sandbox_path.name,
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
            "venv_path": str(venv_path) if venv_path else None,
            "workspace_path": str(sandbox_path / "workspace"),
            "logs_path": str(sandbox_path / "logs"),
        }
        
        metadata_path = sandbox_path / "metadata.json"
        with open(metadata_path, "w", encoding="utf-8") as f:
            json.dump(metadata, f, indent=2, ensure_ascii=False)
