#!/usr/bin/env python3
"""Quick demo script to verify Phase 1 implementation works."""

import sys
from pathlib import Path

# Add src to path
sys.path.insert(0, str(Path(__file__).parent.parent))

from src.skill_parser import SkillParser, SkillDefinition

def main():
    """Demonstrate parsing example skills."""
    parser = SkillParser()
    
    # Parse simple example
    print("=" * 60)
    print("Parsing example_skill.md")
    print("=" * 60)
    
    example_path = Path(__file__).parent / "example_skill.md"
    skill = parser.parse(str(example_path))
    
    print(f"Skill Name: {skill.name}")
    print(f"Description: {skill.description[:80]}...")
    print(f"System Prompt Length: {len(skill.system_prompt)} characters")
    print(f"Tools: {skill.get_tool_names()}")
    print(f"Python Version: {skill.environment_requirements.get('python_version', 'Not specified')}")
    print(f"Packages: {skill.environment_requirements.get('packages', [])}")
    print()
    
    # Parse complex example
    print("=" * 60)
    print("Parsing complex_skill.md")
    print("=" * 60)
    
    complex_path = Path(__file__).parent / "complex_skill.md"
    skill2 = parser.parse(str(complex_path))
    
    print(f"Skill Name: {skill2.name}")
    print(f"Description: {skill2.description[:80]}...")
    print(f"Tools: {skill2.get_tool_names()}")
    
    # Show tool details
    print("\nTool Details:")
    for tool_name in skill2.get_tool_names():
        tool = skill2.get_tool_by_name(tool_name)
        if tool:
            print(f"  - {tool.name} ({tool.tool_type.value}): {tool.description}")
    
    print("\n✅ Phase 1 implementation verified!")

if __name__ == "__main__":
    main()
