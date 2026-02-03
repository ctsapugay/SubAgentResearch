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
