defmodule SkillToSandbox.Skills.ParserTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Skills.Parser

  @fixtures_path Path.join([__DIR__, "..", "..", "fixtures"])

  defp fixture(filename) do
    @fixtures_path
    |> Path.join(filename)
    |> File.read!()
  end

  describe "parse/1 with frontend-design SKILL.md" do
    setup do
      {:ok, parsed} = Parser.parse(fixture("frontend_design_skill.md"))
      %{parsed: parsed}
    end

    test "extracts name from frontmatter", %{parsed: parsed} do
      assert parsed["name"] == "frontend-design"
    end

    test "extracts description from frontmatter", %{parsed: parsed} do
      assert parsed["description"] =~ "distinctive, production-grade frontend interfaces"
    end

    test "extracts frontmatter fields", %{parsed: parsed} do
      assert parsed["frontmatter"]["name"] == "frontend-design"
      assert parsed["frontmatter"]["license"] =~ "LICENSE.txt"
    end

    test "detects sections", %{parsed: parsed} do
      assert "Design Thinking" in parsed["sections"]
      assert "Frontend Aesthetics Guidelines" in parsed["sections"]
    end

    test "detects mentioned tools", %{parsed: parsed} do
      # The real SKILL.md mentions code/file writing and browser concepts
      tools = parsed["mentioned_tools"]
      assert is_list(tools)
      assert length(tools) > 0
    end

    test "detects mentioned frameworks", %{parsed: parsed} do
      frameworks = parsed["mentioned_frameworks"]
      assert "React" in frameworks
      assert "Vue" in frameworks
      assert "HTML" in frameworks
      assert "CSS" in frameworks
      assert "JavaScript" in frameworks
    end

    test "detects dependencies", %{parsed: parsed} do
      deps = parsed["mentioned_dependencies"]
      assert "Motion" in deps or "Framer Motion" in deps or "Motion library" in deps
    end

    test "includes raw_guidelines body text", %{parsed: parsed} do
      assert parsed["raw_guidelines"] =~ "Design Thinking"
      assert parsed["raw_guidelines"] =~ "Frontend Aesthetics"
    end
  end

  describe "parse/1 with seed content (simpler SKILL.md)" do
    @seed_content """
    ---
    name: frontend-design
    description: Create distinctive, production-grade frontend interfaces with innovative layouts, creative use of CSS and JavaScript, and thoughtful UX design.
    ---

    # Frontend Design Skill

    You are an expert frontend developer and designer.

    ## Design Thinking

    Every interface should begin with understanding the user's needs.

    ## Frontend Aesthetics Guidelines

    ### Visual Hierarchy
    - Use size, color, and spacing to guide the user's eye

    ### Modern CSS Techniques
    - Use CSS Grid and Flexbox for layouts
    - Consider using Tailwind CSS for rapid prototyping

    ### JavaScript Frameworks
    - React is the primary framework for complex SPAs
    - Vue is excellent for progressive enhancement
    - Consider Svelte for performance-critical applications
    - Next.js for server-rendered React applications

    ### Motion and Animation
    - Use the Motion library for complex animations

    ### Responsive Design
    - Mobile-first approach

    ## Tools Available

    - **File write**: Create and modify HTML, CSS, and JavaScript files
    - **Web search**: Search for design inspiration, documentation, and best practices
    - **Browser**: Preview and test the interface in a browser

    ## Anti-patterns to Avoid

    - Don't use tables for layout
    """

    test "extracts name and description" do
      {:ok, parsed} = Parser.parse(@seed_content)
      assert parsed["name"] == "frontend-design"
      assert parsed["description"] =~ "innovative layouts"
    end

    test "detects tools from seed content" do
      {:ok, parsed} = Parser.parse(@seed_content)
      tools = parsed["mentioned_tools"]
      assert "web_search" in tools
      assert "file_write" in tools
      assert "browser" in tools
    end

    test "detects frameworks from seed content" do
      {:ok, parsed} = Parser.parse(@seed_content)
      frameworks = parsed["mentioned_frameworks"]
      assert "React" in frameworks
      assert "Vue" in frameworks
      assert "Svelte" in frameworks
      assert "Next.js" in frameworks
      assert "HTML" in frameworks
      assert "CSS" in frameworks
      assert "JavaScript" in frameworks
      assert "Tailwind" in frameworks
    end

    test "detects dependencies from seed content" do
      {:ok, parsed} = Parser.parse(@seed_content)
      deps = parsed["mentioned_dependencies"]
      assert "Motion" in deps or "Motion library" in deps
      assert "Tailwind CSS" in deps
    end

    test "extracts sections from seed content" do
      {:ok, parsed} = Parser.parse(@seed_content)
      sections = parsed["sections"]
      assert "Design Thinking" in sections
      assert "Frontend Aesthetics Guidelines" in sections
      assert "Visual Hierarchy" in sections
      assert "Modern CSS Techniques" in sections
      assert "JavaScript Frameworks" in sections
      assert "Motion and Animation" in sections
      assert "Responsive Design" in sections
      assert "Tools Available" in sections
      assert "Anti-patterns to Avoid" in sections
    end
  end

  describe "parse/1 edge cases" do
    test "returns error for nil content" do
      assert {:error, :empty_content} = Parser.parse(nil)
    end

    test "returns error for empty string" do
      assert {:error, :empty_content} = Parser.parse("")
    end

    test "returns error for whitespace-only content" do
      assert {:error, :empty_content} = Parser.parse("   \n  \n  ")
    end

    test "handles content with no frontmatter" do
      content = """
      # My Skill

      ## Section One

      This skill uses React and TypeScript.

      ## Section Two

      It also uses npm for package management.
      """

      {:ok, parsed} = Parser.parse(content)
      assert parsed["name"] == "My Skill"
      assert parsed["description"] == nil
      assert "Section One" in parsed["sections"]
      assert "Section Two" in parsed["sections"]
      assert "React" in parsed["mentioned_frameworks"]
      assert "TypeScript" in parsed["mentioned_frameworks"]
      assert "npm" in parsed["mentioned_frameworks"]
    end

    test "handles frontmatter only, no body" do
      content = """
      ---
      name: minimal-skill
      description: A minimal skill with no body.
      ---
      """

      {:ok, parsed} = Parser.parse(content)
      assert parsed["name"] == "minimal-skill"
      assert parsed["description"] == "A minimal skill with no body."
      assert parsed["sections"] == []
      assert parsed["mentioned_tools"] == []
      assert parsed["mentioned_frameworks"] == []
    end

    test "handles content with invalid YAML frontmatter" do
      content = """
      ---
      name: [invalid yaml
      this is broken: {{{
      ---

      # Some Skill

      Body content here.
      """

      assert {:error, :invalid_frontmatter} = Parser.parse(content)
    end

    test "handles content with body only (no heading)" do
      content = "Just some plain text about Python and Django."

      {:ok, parsed} = Parser.parse(content)
      assert parsed["name"] == nil
      assert "Python" in parsed["mentioned_frameworks"]
      assert "Django" in parsed["mentioned_frameworks"]
    end

    test "handles Python-focused skill" do
      content = """
      ---
      name: data-science
      description: Data science and ML workflows
      ---

      # Data Science Skill

      ## Environment Setup

      Use Python with pip for package management.
      Install packages like Flask and FastAPI for web APIs.

      ## Tools

      - Execute shell commands to run scripts
      - Search the web for documentation
      """

      {:ok, parsed} = Parser.parse(content)
      assert parsed["name"] == "data-science"
      assert "Python" in parsed["mentioned_frameworks"]
      assert "pip" in parsed["mentioned_frameworks"]
      assert "Flask" in parsed["mentioned_frameworks"]
      assert "FastAPI" in parsed["mentioned_frameworks"]
      assert "web_search" in parsed["mentioned_tools"]
      assert "cli_execution" in parsed["mentioned_tools"]
    end

    test "deduplicates detected items" do
      content = """
      ---
      name: test-skill
      ---

      React React React. Use React for everything.
      CSS CSS CSS. Use CSS for styling.
      """

      {:ok, parsed} = Parser.parse(content)
      react_count = Enum.count(parsed["mentioned_frameworks"], &(&1 == "React"))
      css_count = Enum.count(parsed["mentioned_frameworks"], &(&1 == "CSS"))
      assert react_count == 1
      assert css_count == 1
    end
  end
end
