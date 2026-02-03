#!/usr/bin/env python3
"""
Example usage script for the Skill-to-Sandbox Pipeline.

This script demonstrates how to:
1. Parse a skill file
2. Create a sandbox from a skill
3. Execute tools within the sandbox
4. Clean up resources

Run this script from the project root directory.
"""

import sys
from pathlib import Path

# Add project root to Python path
PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src import SandboxBuilder


def main():
    """Demonstrate basic usage of the SandboxBuilder."""
    
    print("=" * 60)
    print("Skill-to-Sandbox Pipeline - Example Usage")
    print("=" * 60)
    print()
    
    # Initialize the sandbox builder
    print("1. Initializing SandboxBuilder...")
    builder = SandboxBuilder(sandbox_base_path=str(PROJECT_ROOT / "sandboxes"))
    print("   ✓ SandboxBuilder initialized")
    print()
    
    # Example 1: Build sandbox from a skill file
    print("2. Building sandbox from skill file...")
    skill_path = PROJECT_ROOT / "examples" / "simple_skill.md"
    
    if not skill_path.exists():
        print(f"   ✗ Skill file not found: {skill_path}")
        return
    
    try:
        sandbox_id = builder.build_from_skill_file(str(skill_path))
        print(f"   ✓ Sandbox created with ID: {sandbox_id}")
        print()
    except Exception as e:
        print(f"   ✗ Failed to create sandbox: {e}")
        return
    
    # Example 2: Get sandbox information
    print("3. Getting sandbox information...")
    try:
        info = builder.get_sandbox_info(sandbox_id)
        if info:
            print(f"   ✓ Sandbox Name: {info['skill_name']}")
            print(f"   ✓ Description: {info['skill_description'][:60]}...")
            print(f"   ✓ Available Tools: {', '.join(info['tools'])}")
            print(f"   ✓ Workspace Path: {info['workspace_path']}")
        print()
    except Exception as e:
        print(f"   ✗ Failed to get sandbox info: {e}")
        return
    
    # Example 3: Execute tools in the sandbox
    print("4. Executing tools in the sandbox...")
    
    # Write a file
    print("   a) Writing a file...")
    try:
        result = builder.execute_in_sandbox(
            sandbox_id,
            "write_file",
            file_path="example.txt",
            content="Hello from the sandbox!\nThis is a test file."
        )
        print(f"      ✓ File written: {result.get('file_path', 'unknown')}")
        print(f"      ✓ Bytes written: {result.get('bytes_written', 0)}")
    except Exception as e:
        print(f"      ✗ Failed to write file: {e}")
        return
    
    # Read the file back
    print("   b) Reading the file back...")
    try:
        content = builder.execute_in_sandbox(
            sandbox_id,
            "read_file",
            file_path="example.txt"
        )
        print(f"      ✓ File content:")
        print(f"        {repr(content[:50])}...")
    except Exception as e:
        print(f"      ✗ Failed to read file: {e}")
        return
    
    # List files
    print("   c) Listing files in workspace...")
    try:
        files = builder.execute_in_sandbox(
            sandbox_id,
            "list_files",
            directory_path="."
        )
        print(f"      ✓ Found {len(files)} files:")
        for file in files[:5]:  # Show first 5 files
            print(f"        - {file}")
        if len(files) > 5:
            print(f"        ... and {len(files) - 5} more")
    except Exception as e:
        print(f"      ✗ Failed to list files: {e}")
        return
    
    print()
    
    # Example 4: List available tools
    print("5. Listing available tools...")
    try:
        tools = builder.list_tools(sandbox_id)
        print(f"   ✓ Available tools: {', '.join(tools)}")
        print()
    except Exception as e:
        print(f"   ✗ Failed to list tools: {e}")
        return
    
    # Example 5: Clean up
    print("6. Cleaning up sandbox...")
    try:
        builder.cleanup(sandbox_id)
        print(f"   ✓ Sandbox {sandbox_id} cleaned up")
        print()
    except Exception as e:
        print(f"   ✗ Failed to cleanup: {e}")
        return
    
    print("=" * 60)
    print("Example completed successfully!")
    print("=" * 60)


def example_multiple_sandboxes():
    """Demonstrate creating and managing multiple sandboxes."""
    
    print("\n" + "=" * 60)
    print("Multiple Sandboxes Example")
    print("=" * 60)
    print()
    
    builder = SandboxBuilder(sandbox_base_path=str(PROJECT_ROOT / "sandboxes"))
    
    # Create multiple sandboxes
    skill_files = [
        PROJECT_ROOT / "examples" / "simple_skill.md",
        PROJECT_ROOT / "examples" / "example_skill.md",
    ]
    
    sandbox_ids = []
    for skill_file in skill_files:
        if skill_file.exists():
            try:
                sandbox_id = builder.build_from_skill_file(str(skill_file))
                sandbox_ids.append((sandbox_id, skill_file.name))
                print(f"✓ Created sandbox from {skill_file.name}: {sandbox_id}")
            except Exception as e:
                print(f"✗ Failed to create sandbox from {skill_file.name}: {e}")
    
    print()
    print(f"Created {len(sandbox_ids)} sandboxes")
    print()
    
    # Each sandbox is isolated - write different files to each
    for sandbox_id, skill_name in sandbox_ids:
        try:
            builder.execute_in_sandbox(
                sandbox_id,
                "write_file",
                file_path="test.txt",
                content=f"Content from {skill_name}"
            )
            content = builder.execute_in_sandbox(
                sandbox_id,
                "read_file",
                file_path="test.txt"
            )
            print(f"Sandbox {sandbox_id[:8]}... ({skill_name}): {content}")
        except Exception as e:
            print(f"Error in sandbox {sandbox_id}: {e}")
    
    print()
    
    # Clean up all sandboxes
    print("Cleaning up all sandboxes...")
    for sandbox_id, skill_name in sandbox_ids:
        try:
            builder.cleanup(sandbox_id)
            print(f"✓ Cleaned up {skill_name}")
        except Exception as e:
            print(f"✗ Failed to cleanup {skill_name}: {e}")


if __name__ == "__main__":
    # Run the main example
    main()
    
    # Uncomment to run the multiple sandboxes example
    # example_multiple_sandboxes()
