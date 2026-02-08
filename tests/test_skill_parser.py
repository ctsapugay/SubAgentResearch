"""Tests for skill parser."""

import pytest
from pathlib import Path
from src.skill_parser.parser import SkillParser
from src.skill_parser.skill_definition import ToolType


class TestSkillParser:
    """Tests for SkillParser class."""
    
    @pytest.fixture
    def parser(self):
        """Create a SkillParser instance."""
        return SkillParser()
    
    @pytest.fixture
    def example_skill_path(self):
        """Path to example skill file."""
        return Path(__file__).parent.parent / "examples" / "example_skill.md"
    
    @pytest.fixture
    def complex_skill_path(self):
        """Path to complex skill file."""
        return Path(__file__).parent.parent / "examples" / "complex_skill.md"
    
    def test_parse_simple_skill(self, parser, example_skill_path):
        """Test parsing a simple skill file."""
        skill = parser.parse(str(example_skill_path))
        
        assert skill.name == "Web Research Assistant"
        assert "researching topics" in skill.description.lower()
        assert "web research assistant" in skill.system_prompt.lower()
        assert len(skill.tools) >= 3  # Should have web_search, read_file, write_file
        assert "python_version" in skill.environment_requirements
        assert skill.environment_requirements["python_version"] == "3.11"
        assert "packages" in skill.environment_requirements
        assert len(skill.environment_requirements["packages"]) >= 2
    
    def test_parse_complex_skill(self, parser, complex_skill_path):
        """Test parsing a complex skill file."""
        skill = parser.parse(str(complex_skill_path))
        
        assert skill.name == "Frontend Design Specialist"
        assert "frontend" in skill.description.lower()
        assert "frontend design specialist" in skill.system_prompt.lower()
        assert len(skill.tools) >= 4
        assert "python_version" in skill.environment_requirements
    
    def test_parse_nonexistent_file(self, parser):
        """Test that parsing nonexistent file raises FileNotFoundError."""
        with pytest.raises(FileNotFoundError):
            parser.parse("nonexistent_skill.md")
    
    def test_extract_tools_from_section(self, parser, example_skill_path):
        """Test that tools are extracted from Tools section."""
        skill = parser.parse(str(example_skill_path))
        
        tool_names = skill.get_tool_names()
        assert "web_search" in tool_names
        assert "read_file" in tool_names
        assert "write_file" in tool_names
    
    def test_tool_type_inference(self, parser, example_skill_path):
        """Test that tool types are correctly inferred."""
        skill = parser.parse(str(example_skill_path))
        
        web_search_tool = skill.get_tool_by_name("web_search")
        assert web_search_tool is not None
        assert web_search_tool.tool_type == ToolType.WEB_SEARCH
        
        read_file_tool = skill.get_tool_by_name("read_file")
        assert read_file_tool is not None
        assert read_file_tool.tool_type == ToolType.FILESYSTEM
    
    def test_extract_python_version(self, parser, example_skill_path):
        """Test that Python version is extracted correctly."""
        skill = parser.parse(str(example_skill_path))
        
        assert "python_version" in skill.environment_requirements
        assert skill.environment_requirements["python_version"] == "3.11"
    
    def test_extract_packages(self, parser, example_skill_path):
        """Test that packages are extracted correctly."""
        skill = parser.parse(str(example_skill_path))
        
        assert "packages" in skill.environment_requirements
        packages = skill.environment_requirements["packages"]
        assert "requests" in packages
        assert "beautifulsoup4" in packages
    
    def test_metadata_extraction(self, parser, example_skill_path):
        """Test that metadata is extracted correctly."""
        skill = parser.parse(str(example_skill_path))
        
        assert "file_path" in skill.metadata
        assert "source" in skill.metadata
        assert skill.metadata["source"] == "file"
        assert Path(skill.metadata["file_path"]).exists()
    
    def test_parse_skill_without_tools_section(self, parser, tmp_path):
        """Test parsing a skill without explicit Tools section."""
        skill_content = """# Test Skill

## Description
A test skill without tools section.

## System Prompt
You are a test assistant.
"""
        skill_file = tmp_path / "test_skill.md"
        skill_file.write_text(skill_content)
        
        skill = parser.parse(str(skill_file))
        
        assert skill.name == "Test Skill"
        assert skill.description == "A test skill without tools section."
        # Should still work, just with empty tools list or inferred tools
        assert isinstance(skill.tools, list)
    
    def test_parse_skill_without_description_section(self, parser, tmp_path):
        """Test parsing a skill without Description section."""
        skill_content = """# Test Skill

This is a paragraph that should become the description.

## System Prompt
You are a test assistant.
"""
        skill_file = tmp_path / "test_skill.md"
        skill_file.write_text(skill_content)
        
        skill = parser.parse(str(skill_file))
        
        assert skill.name == "Test Skill"
        assert "paragraph" in skill.description.lower()
    
    def test_parse_skill_without_system_prompt_section(self, parser, tmp_path):
        """Test parsing a skill without System Prompt section."""
        skill_content = """# Test Skill

## Description
A test skill.

This paragraph should become the system prompt.
"""
        skill_file = tmp_path / "test_skill.md"
        skill_file.write_text(skill_content)
        
        skill = parser.parse(str(skill_file))
        
        # Should fall back to description
        assert skill.system_prompt is not None
        assert len(skill.system_prompt) > 0
    
    def test_parse_empty_file(self, parser, tmp_path):
        """Test parsing an empty file."""
        skill_file = tmp_path / "empty_skill.md"
        skill_file.write_text("")
        
        # Should handle gracefully - might use filename as name
        skill = parser.parse(str(skill_file))
        assert skill.name is not None
        assert len(skill.name) > 0
    
    def test_parse_skill_name_from_filename(self, parser, tmp_path):
        """Test that skill name is extracted from filename if no title."""
        skill_content = """# 

Some content here.
"""
        skill_file = tmp_path / "my_custom_skill.md"
        skill_file.write_text(skill_content)
        
        skill = parser.parse(str(skill_file))
        
        # Should use filename
        assert "custom" in skill.name.lower() or "skill" in skill.name.lower()

    # ------------------------------------------------------------------ #
    # Frontmatter parsing tests (Task 3 — Phase 6)
    # ------------------------------------------------------------------ #

    def test_parse_frontmatter_skill(self, parser, tmp_path):
        """Test parsing a skill with YAML frontmatter.
        
        Verifies that name and description come from the frontmatter and the
        system_prompt is the markdown body after the closing ---.
        """
        skill_content = """---
name: test-skill
description: A simple test skill with frontmatter.
---

# Test Skill

You are a helpful assistant that does test things.
"""
        skill_file = tmp_path / "frontmatter_skill.md"
        skill_file.write_text(skill_content)

        skill = parser.parse(str(skill_file))

        assert skill.name == "test-skill"
        assert skill.description == "A simple test skill with frontmatter."
        assert "helpful assistant" in skill.system_prompt
        assert "# Test Skill" in skill.system_prompt

    def test_parse_frontmatter_with_multiline_description(self, parser, tmp_path):
        """Test parsing a skill with a multiline YAML description using |."""
        skill_content = """---
name: multiline-skill
description: |
  This is a multiline description that spans
  multiple lines using the YAML pipe syntax.
---

Body content here.
"""
        skill_file = tmp_path / "multiline_skill.md"
        skill_file.write_text(skill_content)

        skill = parser.parse(str(skill_file))

        assert skill.name == "multiline-skill"
        assert "multiline description" in skill.description
        assert "multiple lines" in skill.description
        assert "Body content here." in skill.system_prompt

    def test_parse_frontmatter_extra_fields_in_metadata(self, parser, tmp_path):
        """Test that extra frontmatter fields (beyond name/description) are stored in metadata."""
        skill_content = """---
name: extras-skill
description: Skill with extra fields.
license: MIT
custom_field: hello
---

Some body.
"""
        skill_file = tmp_path / "extras_skill.md"
        skill_file.write_text(skill_content)

        skill = parser.parse(str(skill_file))

        assert skill.metadata.get('license') == 'MIT'
        assert skill.metadata.get('custom_field') == 'hello'
        # name and description should NOT be duplicated in metadata
        assert 'name' not in skill.metadata or skill.metadata.get('name') != 'extras-skill'

    def test_parse_frontmatter_format_metadata(self, parser, tmp_path):
        """Test that frontmatter skills have metadata['format'] == 'frontmatter'."""
        skill_content = """---
name: format-check
description: Checking the format metadata field.
---

Body.
"""
        skill_file = tmp_path / "format_skill.md"
        skill_file.write_text(skill_content)

        skill = parser.parse(str(skill_file))

        assert skill.metadata.get('format') == 'frontmatter'

    def test_parse_frontmatter_tools_inferred_from_body(self, parser, tmp_path):
        """Test that tools are inferred from body content when no ## Tools section exists."""
        skill_content = """---
name: tool-inference
description: Skill whose body mentions read_file and write_file.
---

Use read_file to inspect the project, then write_file to save results.
"""
        skill_file = tmp_path / "tool_inference_skill.md"
        skill_file.write_text(skill_content)

        skill = parser.parse(str(skill_file))

        tool_names = skill.get_tool_names()
        assert "read_file" in tool_names
        assert "write_file" in tool_names

    def test_parse_frontmatter_backward_compatibility(self, parser):
        """Test that heading-based example skills still parse correctly after changes."""
        examples_dir = Path(__file__).parent.parent / "examples"

        # example_skill.md — heading-based
        example_skill = parser.parse(str(examples_dir / "example_skill.md"))
        assert example_skill.name == "Web Research Assistant"
        assert "researching topics" in example_skill.description.lower()
        assert len(example_skill.tools) >= 3
        # Should NOT have frontmatter format tag
        assert example_skill.metadata.get('format') != 'frontmatter'

        # simple_skill.md — heading-based
        simple_skill = parser.parse(str(examples_dir / "simple_skill.md"))
        assert simple_skill.name is not None
        assert len(simple_skill.name) > 0
        assert simple_skill.metadata.get('format') != 'frontmatter'

    def test_parse_real_world_cursor_create_rule(self, parser):
        """Test parsing the real-world Cursor create-rule skill."""
        skill_path = Path(__file__).parent.parent / "examples" / "real_world" / "cursor_create_rule.md"
        skill = parser.parse(str(skill_path))

        assert skill.name == "create-rule"
        assert skill.description.startswith("Create Cursor rules")
        assert "# Creating Cursor Rules" in skill.system_prompt
        assert skill.metadata.get('format') == 'frontmatter'

    def test_parse_real_world_anthropic_frontend_design(self, parser):
        """Test parsing the real-world Anthropic frontend-design skill."""
        skill_path = Path(__file__).parent.parent / "examples" / "real_world" / "anthropic_frontend_design.md"
        skill = parser.parse(str(skill_path))

        assert skill.name == "frontend-design"
        assert skill.description.startswith("Create distinctive")
        assert "Design Thinking" in skill.system_prompt
        assert skill.metadata.get('license') is not None
        assert skill.metadata.get('format') == 'frontmatter'

    def test_parse_real_world_community_deep_research(self, parser):
        """Test parsing the real-world community deep-research skill."""
        skill_path = Path(__file__).parent.parent / "examples" / "real_world" / "community_deep_research.md"
        skill = parser.parse(str(skill_path))

        assert skill.name == "deep-research"
        assert "research reports" in skill.description
        assert "Core Workflow" in skill.system_prompt
        assert "Evidence Collection" in skill.system_prompt
        assert skill.metadata.get('format') == 'frontmatter'
