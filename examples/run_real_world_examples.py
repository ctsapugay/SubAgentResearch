#!/usr/bin/env python3
"""
Run real-world skill examples through the Skill-to-Sandbox pipeline.

Demonstrates that the pipeline correctly handles YAML frontmatter skills
from Cursor, Anthropic Claude Code, and community repositories.

Uses Docker container-based isolation by default. Pass --directory to use
directory-based isolation instead (no Docker required).
"""

import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(PROJECT_ROOT))

from src.sandbox_builder import SandboxBuilder
from src.skill_parser.parser import SkillParser


def run_skill(builder: SandboxBuilder, parser: SkillParser, skill_path: Path):
    """Run a single skill through the pipeline."""
    print(f"\n{'='*60}")
    print(f"Skill: {skill_path.name}")
    print(f"{'='*60}")

    # Step 1: Parse
    print("\n[1] Parsing skill file...")
    skill = parser.parse(str(skill_path))
    print(f"    Name:        {skill.name}")
    print(f"    Description: {skill.description[:80]}...")
    print(f"    Prompt len:  {len(skill.system_prompt)} chars")
    print(f"    Tools:       {skill.get_tool_names() or '(none detected)'}")
    print(f"    Env reqs:    {skill.environment_requirements or '(none)'}")
    print(f"    Metadata:    { {k: v for k, v in skill.metadata.items() if k != 'file_path'} }")

    # Step 2: Create sandbox
    print("\n[2] Creating sandbox...")
    sandbox_id = builder.build_from_skill_file(str(skill_path))
    print(f"    Sandbox ID:  {sandbox_id}")

    # Step 3: Inspect
    print("\n[3] Sandbox info...")
    info = builder.get_sandbox_info(sandbox_id)
    if info:
        print(f"    Skill name:  {info['skill_name']}")
        print(f"    Isolation:   {info['isolation_mode']}")
        if info.get('container_id'):
            print(f"    Container:   {info['container_id'][:12]}")
        print(f"    Tools:       {info['tools']}")
        print(f"    Workspace:   {info['workspace_path']}")

    # Step 4: Execute filesystem tools (if available)
    available_tools = builder.list_tools(sandbox_id)
    print(f"\n[4] Available tools: {available_tools}")

    if "write_file" in available_tools:
        print("    Writing test file...")
        result = builder.execute_in_sandbox(
            sandbox_id, "write_file",
            file_path="pipeline_test.txt",
            content=f"Sandbox created from: {skill.name}\nDescription: {skill.description[:100]}"
        )
        print(f"    Write result: {result}")

    if "read_file" in available_tools:
        print("    Reading test file...")
        content = builder.execute_in_sandbox(
            sandbox_id, "read_file",
            file_path="pipeline_test.txt"
        )
        print(f"    Read content: {repr(content[:80])}...")

    if "list_files" in available_tools:
        print("    Listing files...")
        files = builder.execute_in_sandbox(
            sandbox_id, "list_files",
            directory_path="."
        )
        print(f"    Files: {files}")

    # Step 5: Cleanup
    print("\n[5] Cleaning up...")
    builder.cleanup(sandbox_id)
    print("    Done.")


def main():
    print("="*60)
    print("Real-World Skill Examples — Pipeline Test")
    print("="*60)

    real_world_dir = PROJECT_ROOT / "examples" / "real_world"
    if not real_world_dir.exists():
        print(f"ERROR: {real_world_dir} does not exist. Run Task 1 first.")
        sys.exit(1)

    skill_files = sorted(real_world_dir.glob("*.md"))
    if not skill_files:
        print(f"ERROR: No .md files found in {real_world_dir}")
        sys.exit(1)

    print(f"\nFound {len(skill_files)} real-world skills:")
    for f in skill_files:
        print(f"  - {f.name}")

    # Parse CLI flag for isolation mode
    isolation_mode = "container"
    if "--directory" in sys.argv:
        isolation_mode = "directory"

    print(f"\nIsolation mode: {isolation_mode}")
    if isolation_mode == "container":
        print("  (Docker containers — pass --directory to skip Docker)\n")
    else:
        print("  (local directories — no Docker)\n")

    builder = SandboxBuilder(
        sandbox_base_path=str(PROJECT_ROOT / "sandboxes"),
        isolation_mode=isolation_mode
    )
    parser = SkillParser()

    results = {}
    for skill_path in skill_files:
        try:
            run_skill(builder, parser, skill_path)
            results[skill_path.name] = "PASS"
        except Exception as e:
            print(f"\n    ERROR: {e}")
            import traceback
            traceback.print_exc()
            results[skill_path.name] = f"FAIL: {e}"

    # Summary
    print(f"\n\n{'='*60}")
    print("SUMMARY")
    print(f"{'='*60}")
    for name, status in results.items():
        icon = "✓" if status == "PASS" else "✗"
        print(f"  {icon} {name}: {status}")

    failures = [n for n, s in results.items() if s != "PASS"]
    if failures:
        print(f"\n{len(failures)} skill(s) failed.")
        sys.exit(1)
    else:
        print(f"\nAll {len(results)} skills passed!")


if __name__ == "__main__":
    main()
