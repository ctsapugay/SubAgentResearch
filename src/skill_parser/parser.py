"""Parser for reading and parsing SKILL.md files into SkillDefinition objects."""

import re
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import yaml

from .skill_definition import SkillDefinition, Tool, ToolType


class SkillParser:
    """Parses SKILL.md files into SkillDefinition objects."""
    
    def __init__(self):
        """Initialize the skill parser."""
        pass
    
    def parse(self, skill_path: str) -> SkillDefinition:
        """
        Parse a SKILL.md file into a SkillDefinition.
        
        Supports two formats:
        1. YAML frontmatter (real-world skills): name and description from
           frontmatter, markdown body is the system prompt.
        2. Heading-based (legacy/toy skills): name from # title, description
           from ## Description, system prompt from ## System Prompt, etc.
        
        Args:
            skill_path: Path to the SKILL.md file
            
        Returns:
            SkillDefinition object
            
        Raises:
            FileNotFoundError: If the skill file doesn't exist
            ValueError: If the file cannot be parsed
        """
        path = Path(skill_path)
        if not path.exists():
            raise FileNotFoundError(f"Skill file not found: {skill_path}")
        
        content = path.read_text(encoding='utf-8')
        
        # Try frontmatter parsing first
        frontmatter, body = self._parse_frontmatter(content)
        
        if frontmatter:
            # Frontmatter format: name and description from YAML, body is system prompt
            name = frontmatter.get('name', self._extract_name(body, path))
            description = frontmatter.get('description', '').strip() if isinstance(
                frontmatter.get('description', ''), str
            ) else str(frontmatter.get('description', '')).strip()
            if not description:
                description = self._extract_description(body)
            system_prompt = body.strip()
            if not system_prompt:
                system_prompt = description
        else:
            # Legacy heading-based format (existing logic)
            name = self._extract_name(content, path)
            description = self._extract_description(content)
            system_prompt = self._extract_system_prompt(content)
        
        # Tools: try heading-based extraction on body, fall back to content inference
        tools = self._extract_tools(body if frontmatter else content)
        
        # Environment: try heading-based extraction on body
        environment_requirements = self._extract_environment_requirements(
            body if frontmatter else content
        )
        
        # Metadata: include frontmatter extras
        metadata = self._extract_metadata(content, path)
        if frontmatter:
            metadata['format'] = 'frontmatter'
            # Preserve any extra frontmatter fields (like license, disable-model-invocation, etc.)
            for key, value in frontmatter.items():
                if key not in ('name', 'description'):
                    metadata[key] = value
        
        return SkillDefinition(
            name=name,
            description=description,
            system_prompt=system_prompt,
            tools=tools,
            environment_requirements=environment_requirements,
            metadata=metadata
        )
    
    def _parse_frontmatter(self, content: str) -> Tuple[Optional[Dict[str, Any]], str]:
        """Parse YAML frontmatter from content if present.
        
        Detects content that starts with a ``---`` line, extracts the YAML block
        up to the closing ``---``, and returns the parsed dict plus the remaining
        body text.
        
        Args:
            content: Raw file content.
            
        Returns:
            Tuple of (frontmatter_dict, body_content).
            If no frontmatter is found, returns (None, content).
        """
        stripped = content.strip()
        if not stripped.startswith('---'):
            return (None, content)
        
        # Find the closing --- (the opening --- is at position 0)
        end_index = stripped.find('---', 3)
        if end_index == -1:
            return (None, content)
        
        yaml_text = stripped[3:end_index].strip()
        body = stripped[end_index + 3:]
        
        try:
            frontmatter = yaml.safe_load(yaml_text)
            if not isinstance(frontmatter, dict):
                return (None, content)
            return (frontmatter, body)
        except yaml.YAMLError:
            return (None, content)
    
    def _extract_name(self, content: str, path: Path) -> str:
        """Extract skill name from markdown title or filename."""
        # Check each line individually to avoid cross-line matching issues
        for line in content.split('\n'):
            line = line.strip()
            # Look for # heading with actual content (not just whitespace)
            if line.startswith('#') and len(line) > 1:
                # Extract text after # and whitespace
                name = line[1:].strip()
                # Only use if it has actual non-whitespace content
                if name:
                    return name
        
        # Fall back to filename without extension
        return path.stem.replace('_', ' ').replace('-', ' ').title()
    
    def _extract_description(self, content: str) -> str:
        """Extract description from Description section or first paragraph."""
        # Try to find ## Description section
        desc_match = re.search(
            r'##\s+Description\s*\n\n?(.+?)(?=\n##|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        if desc_match:
            desc = desc_match.group(1).strip()
            # Remove markdown formatting
            desc = re.sub(r'\*\*(.+?)\*\*', r'\1', desc)
            desc = re.sub(r'`(.+?)`', r'\1', desc)
            return desc
        
        # Fall back to first paragraph after title
        # Skip the title line and get first non-empty paragraph
        lines = content.split('\n')
        paragraphs = []
        current_para = []
        
        for line in lines:
            line = line.strip()
            # Skip title and empty lines at start
            if line.startswith('#') or (not paragraphs and not line):
                continue
            if line:
                current_para.append(line)
            elif current_para:
                paragraphs.append(' '.join(current_para))
                current_para = []
        
        if current_para:
            paragraphs.append(' '.join(current_para))
        
        if paragraphs:
            return paragraphs[0]
        
        return "No description provided"
    
    def _extract_system_prompt(self, content: str) -> str:
        """Extract system prompt from System Prompt or Instructions section."""
        # Try ## System Prompt
        prompt_match = re.search(
            r'##\s+System\s+Prompt\s*\n\n?(.+?)(?=\n##|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        if prompt_match:
            return prompt_match.group(1).strip()
        
        # Try ## Instructions
        instructions_match = re.search(
            r'##\s+Instructions\s*\n\n?(.+?)(?=\n##|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        if instructions_match:
            return instructions_match.group(1).strip()
        
        # Default: use description as system prompt
        return self._extract_description(content)
    
    def _extract_tools(self, content: str) -> List[Tool]:
        """Extract tools from Tools section or by searching content."""
        tools = []
        
        # Try to find ## Tools section
        tools_match = re.search(
            r'##\s+Tools\s*\n\n?(.+?)(?=\n##|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        
        if tools_match:
            tools_section = tools_match.group(1)
            # Parse list items (markdown list format)
            # Match lines starting with - or *
            tool_lines = re.findall(r'^[-*]\s*(.+)$', tools_section, re.MULTILINE)
            
            for tool_line in tool_lines:
                tool = self._parse_tool_line(tool_line)
                if tool:
                    tools.append(tool)
        
        # Also search for common tool mentions in content
        if not tools:
            # Look for patterns like "web_search", "read_file", etc.
            common_tools = {
                'web_search': ToolType.WEB_SEARCH,
                'read_file': ToolType.FILESYSTEM,
                'write_file': ToolType.FILESYSTEM,
                'list_files': ToolType.FILESYSTEM,
                'codebase_search': ToolType.CODEBASE_SEARCH,
                'code_search': ToolType.CODEBASE_SEARCH,
                'execute_code': ToolType.CODE_EXECUTION,
                'run_code': ToolType.CODE_EXECUTION,
            }
            
            content_lower = content.lower()
            for tool_name, tool_type in common_tools.items():
                if tool_name in content_lower:
                    # Check if we already have this tool
                    if not any(t.name == tool_name for t in tools):
                        tools.append(Tool(
                            name=tool_name,
                            tool_type=tool_type,
                            description=f"Tool for {tool_name.replace('_', ' ')}"
                        ))
        
        return tools
    
    def _parse_tool_line(self, tool_line: str) -> Optional[Tool]:
        """Parse a single tool line from the Tools section."""
        tool_line = tool_line.strip()
        if not tool_line:
            return None
        
        # Format: "tool_name: description" or "tool_name - description"
        # Or just "tool_name"
        # Use character class with dash at end or escaped
        parts = re.split(r'[:\s-]+', tool_line, maxsplit=1)
        tool_name = parts[0].strip()
        
        if len(parts) > 1:
            description = parts[1].strip()
        else:
            description = f"Tool for {tool_name.replace('_', ' ')}"
        
        # Infer tool type from name
        tool_type = self._infer_tool_type(tool_name)
        
        return Tool(
            name=tool_name,
            tool_type=tool_type,
            description=description
        )
    
    def _infer_tool_type(self, tool_name: str) -> ToolType:
        """Infer tool type from tool name."""
        tool_name_lower = tool_name.lower()
        
        filesystem_keywords = ['read', 'write', 'file', 'list', 'directory', 'dir']
        web_keywords = ['web', 'fetch', 'url', 'http']
        codebase_keywords = ['codebase', 'code_search']
        execution_keywords = ['execute', 'run', 'exec', 'eval']
        database_keywords = ['database', 'db', 'query', 'sql']
        
        # Check codebase first (before web_search, since codebase_search contains "search")
        if any(kw in tool_name_lower for kw in codebase_keywords):
            return ToolType.CODEBASE_SEARCH
        elif any(kw in tool_name_lower for kw in filesystem_keywords):
            return ToolType.FILESYSTEM
        elif any(kw in tool_name_lower for kw in web_keywords) or 'search' in tool_name_lower:
            return ToolType.WEB_SEARCH
        elif any(kw in tool_name_lower for kw in execution_keywords):
            return ToolType.CODE_EXECUTION
        elif any(kw in tool_name_lower for kw in database_keywords):
            return ToolType.DATABASE
        else:
            return ToolType.CUSTOM
    
    def _extract_environment_requirements(self, content: str) -> Dict[str, Any]:
        """Extract environment requirements from Requirements or Environment section."""
        requirements = {}
        
        # Try ## Requirements section
        req_match = re.search(
            r'##\s+Requirements\s*\n\n?(.+?)(?=\n##|\Z)',
            content,
            re.DOTALL | re.IGNORECASE
        )
        
        # Try ## Environment section
        if not req_match:
            req_match = re.search(
                r'##\s+Environment\s*\n\n?(.+?)(?=\n##|\Z)',
                content,
                re.DOTALL | re.IGNORECASE
            )
        
        if req_match:
            req_section = req_match.group(1)
            
            # Extract Python version
            python_match = re.search(r'python\s*([\d.]+)', req_section, re.IGNORECASE)
            if python_match:
                requirements['python_version'] = python_match.group(1)
            
            # Extract packages (lines starting with - or *)
            # Exclude lines that contain "python" (those are version specs, not packages)
            packages = []
            for line in req_section.split('\n'):
                line = line.strip()
                if re.match(r'^[-*]\s+(.+)$', line):
                    package = re.sub(r'^[-*]\s+', '', line).strip()
                    # Skip if it's a Python version line
                    if not re.search(r'python\s*[\d.]', package, re.IGNORECASE):
                        packages.append(package)
            
            if packages:
                requirements['packages'] = packages
        
        return requirements
    
    def _extract_metadata(self, content: str, path: Path) -> Dict[str, Any]:
        """Extract metadata from the skill file."""
        metadata = {
            'file_path': str(path.absolute()),
            'source': 'file'
        }
        
        # Try to extract version if present
        version_match = re.search(r'version\s*[:=]\s*([\d.]+)', content, re.IGNORECASE)
        if version_match:
            metadata['version'] = version_match.group(1)
        
        return metadata
