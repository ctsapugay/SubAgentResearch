# Directory-Based Skills Implementation Plan

**Document Version:** 1.3  
**Last Updated:** 2025-02-24  
**Status:** Approved for Implementation  
**Storage Strategy:** Option A — Store `file_tree` in database (JSON map)

**Revision History:**
- 1.3: Phase 4 complete — SkillLive.New URL (GitHubFetcher), ZIP upload, create_skill_with_parser directory/file
- 1.2: Phase 3 complete — DependencyScanner, Parser.parse_directory, tests
- 1.1: Added gaps analysis — Runner parse logic, ZIP handling, path stripping, binary files, package.json at repo root, implementation order fix, file size limits

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Background and Motivation](#2-background-and-motivation)
3. [Reference Implementation: Agent-Browser Skill](#3-reference-implementation-agent-browser-skill)
4. [Current Architecture Overview](#4-current-architecture-overview)
5. [Data Model Changes](#5-data-model-changes)
6. [Module-by-Module Implementation Plan](#6-module-by-module-implementation-plan)
7. [GitHub API Integration](#7-github-api-integration)
8. [Error Handling and Edge Cases](#8-error-handling-and-edge-cases)
9. [Testing Strategy](#9-testing-strategy)
10. [Migration and Rollback](#10-migration-and-rollback)
11. [Implementation Order](#11-implementation-order)
12. [Acceptance Criteria](#12-acceptance-criteria)
13. [Gaps Analysis and Resolutions](#13-gaps-analysis-and-resolutions)

---

## 1. Executive Summary

This document describes the implementation plan for extending SkillToSandbox to support **directory-based skills** in addition to single-file skills. A directory skill contains multiple files (e.g., `SKILL.md`, `references/*.md`, `templates/*.sh`) that are referenced from the main skill definition. The canonical example is the [agent-browser skill](https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser) from Vercel Labs.

**Key deliverables:**
- Skills can be uploaded as a **directory** (GitHub tree URL or ZIP file) or a **single file** (current behavior)
- The entire skill directory is **copied into the container** at a configurable path (e.g., `/workspace/skill`)
- **All files in the tree** are parsed for dependency hints (tools, frameworks, packages)
- **Dependency files** (`package.json`, `requirements.txt`) in the skill tree are scanned and merged with LLM analysis
- **Backward compatibility** is maintained for existing single-file skills

---

## 2. Background and Motivation

### 2.1 Current Limitation

The current SkillToSandbox implementation assumes skills are **single SKILL.md files**. It stores:
- `raw_content` — the full text of the file
- `source_url` — optional GitHub URL to the file

Many real-world skills (e.g., agent-browser) have:
- A main `SKILL.md` that references additional documentation
- A `references/` directory with detailed markdown files
- A `templates/` directory with executable shell scripts
- Relative paths like `[references/commands.md](references/commands.md)` that must resolve inside the container

### 2.2 Requirements

1. **Support directory skills:** Fetch and store the full file tree when the source is a directory
2. **Copy skill into container:** Place the entire skill directory at a known path (e.g., `/workspace/skill`) so subagents can reference assets
3. **Parse all files:** Extract tools, frameworks, and dependencies from every relevant file in the tree
4. **Discover dependencies:** Scan for `package.json`, `requirements.txt`, etc. and merge with LLM output

---

## 3. Reference Implementation: Agent-Browser Skill

### 3.1 Structure

```
skills/agent-browser/
├── SKILL.md                    # Main definition (~16KB)
├── references/                 # 7 markdown files
│   ├── commands.md
│   ├── authentication.md
│   ├── session-management.md
│   ├── snapshot-refs.md
│   ├── video-recording.md
│   ├── profiling.md
│   └── proxy-support.md
└── templates/                  # 3 executable shell scripts
    ├── form-automation.sh
    ├── authenticated-session.sh
    └── capture-workflow.sh
```

### 3.2 Key Characteristics

- **SKILL.md** contains a "Deep-Dive Documentation" table linking to `references/*.md` and "Ready-to-Use Templates" linking to `templates/*.sh`
- **Templates** are meant to be run as `./templates/form-automation.sh <url>`
- **Frontmatter** includes `allowed-tools: Bash(npx agent-browser:*), Bash(agent-browser:*)`
- **Dependencies:** The agent-browser package (at repo root) has `playwright-core`, `webdriverio`, etc. Playwright requires browser binaries (`npx playwright install chromium`)

### 3.3 URLs

- **Directory:** `https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser`
- **Single file:** `https://github.com/vercel-labs/agent-browser/blob/main/skills/agent-browser/SKILL.md`

### 3.4 GitHub Raw URLs

- Single file: `https://raw.githubusercontent.com/vercel-labs/agent-browser/main/skills/agent-browser/SKILL.md`
- Directory: Use GitHub API (see Section 7)

---

## 4. Current Architecture Overview

### 4.1 Relevant Files

| Path | Purpose |
|------|---------|
| `lib/skill_to_sandbox/skills/skill.ex` | Skill schema |
| `lib/skill_to_sandbox/skills/parser.ex` | Parses SKILL.md content |
| `lib/skill_to_sandbox/skills.ex` | Skills context (CRUD) |
| `lib/skill_to_sandbox/analysis/analyzer.ex` | LLM analysis |
| `lib/skill_to_sandbox/analysis/sandbox_spec.ex` | SandboxSpec schema |
| `lib/skill_to_sandbox/sandbox/build_context.ex` | Assembles Docker build context |
| `lib/skill_to_sandbox/sandbox/dockerfile_builder.ex` | Generates Dockerfile |
| `lib/skill_to_sandbox/pipeline/runner.ex` | Pipeline state machine |
| `lib/skill_to_sandbox_web/live/skill_live/new.ex` | Upload form (paste, file, URL) |

### 4.2 Current Skill Schema (skills table)

```elixir
# Current fields
field :name, :string
field :description, :string
field :source_url, :string
field :raw_content, :string      # NOT NULL
field :parsed_data, :map, default: %{}
```

### 4.3 Current Upload Flow

1. **Paste:** User pastes content → `Parser.parse/1` → `Skills.create_skill/1`
2. **File:** User uploads `.md` → read content → same as paste
3. **URL:** User provides GitHub URL → convert to raw URL → `Req.get` → same as paste

### 4.4 Current Build Flow

1. `BuildContext.assemble(spec)` creates temp dir with: Dockerfile, package.json/requirements.txt, tools/*.sh, tool_manifest.json
2. **Skill content is NOT copied into the container** — it is only used for parsing and LLM analysis
3. `Docker.build_image` and `Docker.run_container` create the sandbox

---

## 5. Data Model Changes

### 5.1 Skill Schema Additions

**New fields (Option A — store in DB):**

| Field | Type | Nullable | Default | Description |
|-------|------|----------|---------|-------------|
| `source_type` | `string` | No | `"file"` | `"file"` or `"directory"` |
| `source_root_url` | `string` | Yes | `nil` | For directory: full GitHub tree URL (e.g., `https://github.com/org/repo/tree/main/skills/agent-browser`) |
| `file_tree` | `map` | Yes | `%{}` | Map of `relative_path => content` (string). Keys use forward slashes, e.g. `"references/commands.md"` |

**Field semantics:**
- `source_type == "file"`: `raw_content` holds the file; `file_tree` may be empty or `%{"SKILL.md" => raw_content}` for consistency
- `source_type == "directory"`: `file_tree` holds all files; `raw_content` **must always be set** to the content of `SKILL.md` (or the primary entry point) so that existing consumers (Parser, Analyzer, Runner, LiveViews) continue to work without modification. When creating a directory skill, derive `raw_content` from `file_tree["SKILL.md"]` or the first `.md` at root.

### 5.2 Migration: Add Skill Directory Support

**File:** `priv/repo/migrations/YYYYMMDDHHMMSS_add_skill_directory_support.exs`

```elixir
defmodule SkillToSandbox.Repo.Migrations.AddSkillDirectorySupport do
  use Ecto.Migration

  def change do
    alter table(:skills) do
      add :source_type, :string, null: false, default: "file"
      add :source_root_url, :string
      add :file_tree, :map, default: %{}
    end
  end
end
```

**Backfill (run after migration):** The backfill is best done in a separate mix task or in `priv/repo/seeds.exs` (for dev) because `raw_content` may contain characters that complicate raw SQL. Create a mix task:

```elixir
# lib/mix/tasks/skill_to_sandbox.backfill_file_tree.ex
defmodule Mix.Tasks.SkillToSandbox.BackfillFileTree do
  use Mix.Task

  @shortdoc "Backfill file_tree for existing skills (source_type=file)"

  def run(_args) do
    Mix.Task.run("app.start")

    import Ecto.Query
    alias SkillToSandbox.Repo
    alias SkillToSandbox.Skills.Skill

    Skill
    |> Repo.all()
    |> Enum.each(fn skill ->
      if skill.file_tree in [nil, %{}] and skill.raw_content do
        Skill.changeset(skill, %{file_tree: %{"SKILL.md" => skill.raw_content}})
        |> Repo.update!()
      end
    end)

    IO.puts("Backfill complete.")
  end
end
```

Run with: `mix skill_to_sandbox.backfill_file_tree`

**Note:** The project uses SQLite (ecto_sqlite3). The `:map` type stores JSON. Ecto handles serialization/deserialization.

### 5.3 Schema Changes in skill.ex

**Updated required/optional fields:**
- `@required_fields ~w(name raw_content)a` — keep `raw_content` required; for directory skills, it is always derived from `file_tree["SKILL.md"]` at creation time
- `@optional_fields ~w(description source_url parsed_data source_type source_root_url file_tree)a`

**Validation rules:**
- `raw_content` must be present and non-empty (always, since we derive it for directory skills)
- If `source_type == "directory"`: `file_tree` must be a non-empty map
- `source_type` must be in `["file", "directory"]` (default `"file"`)
- `file_tree` keys must use forward slashes; values must be strings

### 5.4 SandboxSpec Schema Additions

**New fields:**

| Field | Type | Nullable | Default | Description |
|-------|------|----------|---------|-------------|
| `skill_mount_path` | `string` | Yes | `"/workspace/skill"` | Path inside container where skill directory is copied |
| `post_install_commands` | `JsonData` (list) | Yes | `[]` | Optional list of shell commands to run after dependency install (e.g., `["npx playwright install chromium"]`) |

**Migration** for sandbox_specs:

```elixir
def change do
  alter table(:sandbox_specs) do
    add :skill_mount_path, :string, default: "/workspace/skill"
    add :post_install_commands, :map, default: []  # JSON array, e.g. ["npx playwright install chromium"]
  end
end
```

**Note:** The project uses `JsonData` Ecto type (in `lib/skill_to_sandbox/ecto_types/json_data.ex`) for fields that hold either maps or lists. Add `post_install_commands` to the SandboxSpec schema using `JsonData` (same as `eval_goals` and `system_packages`).

---

## 6. Module-by-Module Implementation Plan

### 6.1 New Module: `SkillToSandbox.Skills.GitHubFetcher`

**Location:** `lib/skill_to_sandbox/skills/git_hub_fetcher.ex`

**Purpose:** Fetch skill content from GitHub, supporting both single files and directories.

**Public API:**

```elixir
@doc """
Fetches content from a GitHub URL. Supports both file and directory URLs.

## Examples

    # Single file
    fetch("https://github.com/org/repo/blob/main/skills/agent-browser/SKILL.md")
    # => {:ok, %{type: :file, content: "...", path: "skills/agent-browser/SKILL.md"}}

    # Directory
    fetch("https://github.com/org/repo/tree/main/skills/agent-browser")
    # => {:ok, %{type: :directory, file_tree: %{"SKILL.md" => "...", "references/commands.md" => "..."}, root_url: "..."}}

    # Error
    fetch("https://github.com/org/repo/blob/main/nonexistent.md")
    # => {:error, :not_found}
"""
@spec fetch(url :: String.t()) ::
  {:ok, %{type: :file, content: String.t(), path: String.t()}} |
  {:ok, %{type: :directory, file_tree: %{String.t() => String.t()}, root_url: String.t()}} |
  {:error, atom() | String.t()}
def fetch(url)
```

**Implementation notes:**
- Parse URL to extract: `owner`, `repo`, `path`, `ref` (branch/tag)
- **File URL** (contains `/blob/`): Use `GET https://raw.githubusercontent.com/{owner}/{repo}/{ref}/{path}` to fetch content
- **Directory URL** (contains `/tree/`): Use GitHub API (see Section 7) to recursively fetch all files
- **Path stripping:** The Git Trees API returns paths like `skills/agent-browser/SKILL.md`. Strip the directory `path` prefix to get keys relative to the skill root. Example: for `path = "skills/agent-browser"`, `skills/agent-browser/SKILL.md` → `SKILL.md`, `skills/agent-browser/references/commands.md` → `references/commands.md`
- **Binary files:** Skip blobs that decode to invalid UTF-8, or skip by extension (`.png`, `.jpg`, `.pdf`, etc.). Skill content is typically text.

### 6.2 New Module: `SkillToSandbox.Skills.DependencyScanner`

**Location:** `lib/skill_to_sandbox/skills/dependency_scanner.ex`

**Purpose:** Scan a file tree for dependency files and extract package information.

**Public API:**

```elixir
@doc """
Scans a file tree for dependency files and returns structured dependency info.

Returns a map with keys:
- :npm / :pip / :yarn / :pnpm — maps of package_name => version
- :package_json — raw parsed package.json if found
- :requirements_txt — parsed requirements if found
"""
@spec scan(file_tree :: %{String.t() => String.t()}) :: %{optional(atom()) => any()}
def scan(file_tree)
```

**Files to scan:**
- `package.json` (anywhere in tree, including `_repo_root/package.json` if GitHubFetcher added it) → extract `dependencies` and `devDependencies`; merge into `runtime_deps`
- `requirements.txt` → parse lines; return `{manager: "pip", packages: %{name => version}}`
- `Pipfile` → optional
- `Cargo.toml` → optional (future)

**Output format:**
```elixir
%{
  npm: %{"react" => "^18.0.0", "agent-browser" => "latest"},
  pip: %{},
  package_json_path: "package.json",  # or nil
  requirements_path: nil
}
```

### 6.3 Changes to `SkillToSandbox.Skills.Parser`

**Location:** `lib/skill_to_sandbox/skills/parser.ex`

**New functions:**

```elixir
@doc """
Parses a directory file tree. Finds SKILL.md (or first .md at root), parses all .md and .sh files,
and merges extracted tools, frameworks, dependencies, sections.

Returns {:ok, parsed_map} with same structure as parse/1.
"""
@spec parse_directory(file_tree :: %{String.t() => String.t()}) :: {:ok, map()} | {:error, atom()}
def parse_directory(file_tree)
```

**Logic:**
1. Find primary file: `SKILL.md` at root, or `file_tree["SKILL.md"]`, or first file matching `*.md` at root
2. For each file in `file_tree` with extension `.md` or `.sh`:
   - Run existing keyword extraction (tools, frameworks, dependencies, sections)
   - Merge results (union of all lists)
3. Use primary file's frontmatter for `name`, `description`
4. Return `%{name, description, sections, mentioned_tools, mentioned_frameworks, mentioned_dependencies, raw_guidelines, frontmatter}`

**Keep `parse/1` unchanged** for backward compatibility.

### 6.4 Changes to `SkillToSandbox.Skills` (Context)

**Location:** `lib/skill_to_sandbox/skills.ex`

- Update `create_skill/1` to accept `source_type`, `source_root_url`, `file_tree`
- When `source_type == "directory"` and `file_tree` is provided:
  - Set `raw_content` from `file_tree["SKILL.md"]` or primary entry point
  - Validate `file_tree` is non-empty

### 6.5 Changes to `SkillToSandbox.Skills.Skill` (Schema)

**Location:** `lib/skill_to_sandbox/skills/skill.ex`

- Add `source_type`, `source_root_url`, `file_tree` to schema
- Update `changeset/2`:
  - If `source_type == "file"`: require `raw_content`
  - If `source_type == "directory"`: require `file_tree` (non-empty map); optionally derive `raw_content`
  - Validate `source_type in ["file", "directory"]`
  - Ensure `file_tree` keys are strings with forward slashes

### 6.6 Changes to `SkillToSandbox.Analysis.Analyzer`

**Location:** `lib/skill_to_sandbox/analysis/analyzer.ex`

**Updates to `build_user_prompt/1`:**
- Call `DependencyScanner.scan(skill.file_tree || %{})` at the start. Include result in prompt.
- If skill has `source_type == "directory"` and `file_tree`:
  - Include a summary: "This skill has multiple files: SKILL.md, references/*.md, templates/*.sh"
  - Include full content of `SKILL.md` and optionally `references/*.md` (or truncate if too long)
  - Include output of `DependencyScanner.scan(skill.file_tree)` in the prompt
- Add instruction: "The skill directory will be mounted at SKILL_PATH in the container. Templates and references are available."

**Merge logic for dependencies:** When DependencyScanner finds `package.json` or `requirements.txt`, instruct the LLM to **prefer** those dependencies over inference. The LLM fills gaps (e.g., system packages, tool configs) and can add packages the Scanner missed. Output: use Scanner's packages as base, merge with LLM suggestions, Scanner wins on conflicts.

**Prompt addition:**
```
If the skill includes a package.json or requirements.txt in its file tree, PREFER those exact dependencies.
The skill directory is copied to /workspace/skill (or SKILL_MOUNT_PATH). Templates may be executable scripts.
```

### 6.7 Changes to `SkillToSandbox.Analysis.SandboxSpec`

**Location:** `lib/skill_to_sandbox/analysis/sandbox_spec.ex`

- Add `skill_mount_path: "/workspace/skill"` (default)
- Add `post_install_commands` (list of strings)
- Update `@optional_fields` and `changeset/2`

### 6.8 Changes to `SkillToSandbox.Sandbox.BuildContext`

**Location:** `lib/skill_to_sandbox/sandbox/build_context.ex`

**Signature change:**
```elixir
# Current
def assemble(%SandboxSpec{} = spec)

# New: pass skill for file_tree access
def assemble(%SandboxSpec{} = spec, %Skill{} = skill)
```

**New step in `assemble/2`:**
1. After writing tool scripts and before finishing:
   - If `skill.source_type == "directory"` and `skill.file_tree != %{}`:
     - Create `skill/` subdirectory in build context
     - For each `{path, content}` in `skill.file_tree`:
       - Write to `Path.join(dir, "skill", path)`
       - Ensure parent directories exist
     - For `.sh` files under `skill/templates/` (or any `*.sh`): `File.chmod!(path, 0o755)`
   - If `skill.source_type == "file"`:
     - Optionally create `skill/SKILL.md` with `skill.raw_content` for consistency

**Call site:** `Pipeline.Runner.execute_docker_build/2` must load the skill and pass it:
```elixir
skill = Skills.get_skill!(spec.skill_id)
with {:ok, context_dir, dockerfile_content} <- BuildContext.assemble(spec, skill), ...
```

### 6.9 Changes to `SkillToSandbox.Sandbox.DockerfileBuilder`

**Location:** `lib/skill_to_sandbox/sandbox/dockerfile_builder.ex`

**New blocks:**
1. `skill_copy_block(spec)` — insert after `tool_setup_block`:
   ```
   # Skill directory (references, templates, etc.)
   COPY skill/ /workspace/skill/
   RUN chmod +x /workspace/skill/templates/*.sh 2>/dev/null || true
   ENV SKILL_PATH=/workspace/skill
   ```
   Use `spec.skill_mount_path` for the destination if different.

2. `post_install_block(spec)` — if `post_install_commands` is non-empty:
   ```
   RUN npx playwright install chromium
   ```
   (Or whatever commands are in the list, joined with `&&`)

**Order in `build/1`:**
- base_image, labels, system_packages, workdir, runtime_deps, **post_install** (if any), tool_setup, **skill_copy** (if skill dir exists), env, entrypoint

**Note:** The skill copy block should only be added when the build context actually has a `skill/` directory. The DockerfileBuilder doesn't have direct access to the skill — it receives the spec. The BuildContext writes the skill dir. So the DockerfileBuilder should **always** include the skill copy block when we have directory skills; the BuildContext ensures the `skill/` dir exists. For single-file skills, BuildContext will write `skill/SKILL.md`, so the COPY will work.

**Simpler approach:** BuildContext always writes a `skill/` directory (either full tree or just SKILL.md). DockerfileBuilder always includes the COPY. No conditional.

### 6.10 Changes to `SkillToSandbox.Pipeline.Runner`

**Location:** `lib/skill_to_sandbox/pipeline/runner.ex`

**1. In `execute_docker_build/2`:** Load skill and pass to BuildContext:
  ```elixir
  skill = Skills.get_skill!(spec.skill_id)
  with {:ok, context_dir, dockerfile_content} <- BuildContext.assemble(spec, skill), ...
  ```

**2. In `do_start_parsing/1`:** Use the correct parser based on `source_type`:
  ```elixir
  # Current: Parser.parse(skill.raw_content)
  # New: branch on source_type
  parse_result =
    if skill.source_type == "directory" and skill.file_tree != %{} do
      Parser.parse_directory(skill.file_tree)
    else
      Parser.parse(skill.raw_content)
    end

  case parse_result do
    {:ok, parsed_data} -> ...
    {:error, reason} -> ...
  end
  ```
  This ensures directory skills have tools/frameworks/deps merged from all files, not just SKILL.md.

### 6.11 Changes to `SkillToSandboxWeb.SkillLive.New`

**Location:** `lib/skill_to_sandbox_web/live/skill_live/new.ex`

**Upload modes:**

1. **Paste:** Update `create_skill_with_parser` to set `file_tree: %{"SKILL.md" => content}` for consistency (so BuildContext always has a skill/ dir to write). Creates `source_type: "file"`, `raw_content: content`, `file_tree: %{"SKILL.md" => content}`.

2. **File upload:** 
   - Accept `.md` (single file) — current behavior; also set `file_tree: %{"SKILL.md" => content}` for consistency
   - Accept `.zip` (new):
     - Use Erlang's `:zip` module: `:zip.unzip(zip_path, [{:cwd, temp_dir}])` or `:zip.extract/2`
     - **Path traversal:** Reject any entry whose path escapes the extraction root (e.g., `../etc/passwd`). Normalize with `Path.expand` and ensure `String.starts_with?(normalized, extraction_root)`.
     - **SKILL.md location:** Find `SKILL.md` (at root or in any subdir). Use its containing directory as the skill root. Keys in `file_tree` are relative to that root. If multiple `SKILL.md` exist, use the shallowest (e.g., root wins over `foo/SKILL.md`).
     - **Limits:** Consider max total size (e.g., 10MB) and max file count (e.g., 200) to prevent abuse.
     - **Cleanup:** Delete temp extraction dir after building `file_tree`.
     - Set `source_type: "directory"`, `file_tree`, `raw_content` from SKILL.md
     - Use `allow_upload` with `accept: ~w(.md .zip)`

3. **URL:**
   - Replace direct `Req.get(raw_url)` with `GitHubFetcher.fetch(url)`
   - If `{:ok, %{type: :file, content: c, path: p}}` → treat like current (single file)
   - If `{:ok, %{type: :directory, file_tree: ft, root_url: u}}`:
     - Set `source_type: "directory"`, `file_tree: ft`, `source_root_url: u`
     - Set `raw_content` from `ft["SKILL.md"]` or primary entry
   - Update `github_url?/1` to accept both `/blob/` and `/tree/` URLs

**Update `create_skill_with_parser/4`:**
- For directory: call `Parser.parse_directory(file_tree)` instead of `Parser.parse(raw_content)`
- For file: keep `Parser.parse(raw_content)`

---

## 7. GitHub API Integration

### 7.1 URL Parsing

**File URL pattern:** `https://github.com/{owner}/{repo}/blob/{ref}/{path}`  
**Directory URL pattern:** `https://github.com/{owner}/{repo}/tree/{ref}/{path}`

**Example:**
- `https://github.com/vercel-labs/agent-browser/blob/main/skills/agent-browser/SKILL.md` → owner=vercel-labs, repo=agent-browser, ref=main, path=skills/agent-browser/SKILL.md
- `https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser` → owner=vercel-labs, repo=agent-browser, ref=main, path=skills/agent-browser

### 7.2 Fetching a Single File

Use raw URL: `https://raw.githubusercontent.com/{owner}/{repo}/{ref}/{path}`

No API key required. Rate limit: 60 requests/hour for unauthenticated requests.

### 7.3 Fetching a Directory (Recursive)

**Option A: Contents API (paginated)**

```
GET https://api.github.com/repos/{owner}/{repo}/contents/{path}?ref={ref}
```

Returns a list of files and directories. For each directory, recurse. For each file, fetch via `download_url` (or raw URL).

**Option B: Git Trees API (single call)**

```
GET https://api.github.com/repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1
```

To get `tree_sha`: first get the commit SHA for the ref:
```
GET https://api.github.com/repos/{owner}/{repo}/commits/{ref}
```
Response includes `commit.tree.sha`. Then:
```
GET https://api.github.com/repos/{owner}/{repo}/git/trees/{tree_sha}?recursive=1
```

Response includes `tree` array with `path`, `sha`, `type` (blob/dir). For each `type: "blob"`, fetch content:
```
GET https://api.github.com/repos/{owner}/{repo}/git/blobs/{sha}
```
Response is base64-encoded. Decode to get content.

**Recommended:** Option B for fewer API calls. Filter `tree` by `path` starting with the skill directory (e.g., `path` = `skills/agent-browser`).

**Repo root package.json:** When the skill path is a subdirectory (e.g., `skills/agent-browser`), optionally fetch `package.json` from repo root (`/package.json`) and add to `file_tree` as `_repo_root/package.json` or merge its dependencies into the scan. This handles skills like agent-browser where the package.json lives at repo root.

### 7.4 Rate Limits

- Unauthenticated: 60 requests/hour
- Authenticated (token in header): 5000 requests/hour

**Recommendation:** Support optional `GITHUB_TOKEN` env var for authenticated requests when fetching directories (many blobs).

### 7.5 Implementation Sketch for GitHubFetcher

```elixir
def fetch(url) do
  case parse_github_url(url) do
    {:ok, %{type: :file, owner: o, repo: r, ref: ref, path: p}} ->
      fetch_file(o, r, ref, p)
    {:ok, %{type: :directory, owner: o, repo: r, ref: ref, path: p}} ->
      fetch_directory(o, r, ref, p)
    {:error, _} = err -> err
  end
end

defp fetch_file(owner, repo, ref, path) do
  raw_url = "https://raw.githubusercontent.com/#{owner}/#{repo}/#{ref}/#{path}"
  case Req.get(raw_url) do
    {:ok, %{status: 200, body: body}} when is_binary(body) ->
      {:ok, %{type: :file, content: body, path: path}}
    {:ok, %{status: 404}} -> {:error, :not_found}
    # ...
  end
end

defp fetch_directory(owner, repo, ref, path) do
  # Get default branch commit, then tree
  # Filter tree to only paths under `path`
  # Fetch each blob, build file_tree with relative paths
  # Return {:ok, %{type: :directory, file_tree: %{}, root_url: url}}
end
```

---

## 8. Error Handling and Edge Cases

### 8.1 GitHub Fetch Errors

| Scenario | Handling |
|----------|----------|
| 404 on file | Return `{:error, :not_found}` |
| 404 on directory | Return `{:error, :not_found}` |
| Rate limited (429) | Retry with backoff, or return `{:error, :rate_limited}` |
| Network error | Return `{:error, reason}` |
| Invalid URL | Return `{:error, :invalid_url}` |
| Empty directory | Return `{:error, :empty_directory}` |
| No SKILL.md in directory | Return `{:error, :no_skill_md}` |

### 8.2 Upload Edge Cases

| Scenario | Handling |
|----------|----------|
| ZIP with no SKILL.md | Show error: "ZIP must contain SKILL.md" |
| ZIP with nested SKILL.md (e.g., `foo/SKILL.md`) | Accept; use containing directory as root for file_tree |
| Very large file tree (>10MB total) | Reject with error or show warning; SQLite handles large blobs but limits prevent abuse |
| Too many files (>200) | Reject with error |
| Binary files in tree | Skip (don't store); detect by invalid UTF-8 or extension |
| Path traversal in ZIP (e.g., `../etc/passwd`) | Reject; validate all paths stay within extraction root |

### 8.3 Parser Edge Cases

| Scenario | Handling |
|----------|----------|
| Multiple SKILL.md in tree | Use root-level SKILL.md; or first found |
| No frontmatter in any file | Use first heading or "Unnamed Skill" |
| Empty file_tree | Return `{:error, :empty_content}` |

### 8.4 Build Edge Cases

| Scenario | Handling |
|----------|----------|
| Skill has no file_tree (legacy) | BuildContext writes `skill/SKILL.md` from raw_content |
| Spec has no skill_mount_path | Use default `/workspace/skill` |
| post_install_commands fail | Docker build fails; user sees error in pipeline |

---

## 9. Testing Strategy

### 9.1 Unit Tests

- **GitHubFetcher:** Mock Req or use fixtures; test URL parsing, file fetch, directory fetch
- **DependencyScanner:** Test with sample package.json, requirements.txt
- **Parser.parse_directory:** Test with agent-browser-like file_tree fixture
- **BuildContext:** Test that skill/ dir is written with correct structure and permissions
- **DockerfileBuilder:** Test that skill_copy_block and post_install_block appear in output

### 9.2 Integration Tests

- **End-to-end:** Upload agent-browser directory URL → pipeline runs → sandbox has `/workspace/skill` with expected files
- **Backward compatibility:** Upload single-file skill → pipeline runs as before

### 9.3 Fixtures

Create `test/fixtures/agent_browser_skill/` with:
- SKILL.md (truncated)
- references/commands.md (truncated)
- templates/form-automation.sh

Use for parser and build context tests.

---

## 10. Migration and Rollback

### 10.1 Migration Order

1. Run skills migration (add source_type, source_root_url, file_tree)
2. Run sandbox_specs migration (add skill_mount_path, post_install_commands)
3. Backfill existing skills: `file_tree = %{"SKILL.md" => raw_content}`, `source_type = "file"`

### 10.2 Rollback

If issues arise:
- Revert code changes
- Migrations can be rolled back (remove columns) — but data in new columns will be lost
- For non-destructive rollback: keep columns, make them optional; old code ignores them

---

## 11. Implementation Order

Execute in this order to minimize integration issues:

1. **Phase 1: Data model** ✅
   - [x] Create migration for skills (source_type, source_root_url, file_tree)
   - [x] Create migration for sandbox_specs (skill_mount_path, post_install_commands)
   - [x] Run migrations: `mix ecto.migrate`
   - [x] Update Skill schema and changeset (add new fields to struct)
   - [x] Update SandboxSpec schema and changeset
   - [x] Update Skills context (create_skill accepts new fields)
   - [x] Create backfill mix task `Mix.Tasks.SkillToSandbox.BackfillFileTree`
   - [x] Run backfill: `mix skill_to_sandbox.backfill_file_tree`

2. **Phase 2: GitHub fetcher** ✅
   - [x] Implement GitHubFetcher module (URL parsing, file fetch, directory fetch)
   - [x] Add tests
   - [x] Optional: GITHUB_TOKEN support for rate limits

3. **Phase 3: Parser and DependencyScanner** ✅
   - [x] Implement DependencyScanner
   - [x] Implement Parser.parse_directory
   - [x] Add tests

4. **Phase 4: Upload flow** ✅
   - [x] Update SkillLive.New: URL mode uses GitHubFetcher
   - [x] Update SkillLive.New: add ZIP upload support
   - [x] Update create_skill_with_parser for directory vs file
   - [x] Update allow_upload to accept .zip

5. **Phase 5: Build pipeline**
   - [ ] Update BuildContext.assemble to accept skill, write skill/ dir
   - [ ] Update DockerfileBuilder: skill_copy_block, post_install_block
   - [ ] Update Runner.execute_docker_build to pass skill
   - [ ] Add ENV SKILL_PATH to container

6. **Phase 6: Analyzer**
   - [ ] Update Analyzer to use file_tree and DependencyScanner when available
   - [ ] Update prompt for directory skills

7. **Phase 7: Testing and polish**
   - [ ] Integration test: agent-browser URL → sandbox
   - [ ] Integration test: single-file backward compat
   - [ ] Update SkillLive.Show to display file tree info for directory skills (optional)
   - [ ] Documentation updates

---

## 12. Acceptance Criteria

- [ ] User can upload agent-browser skill via `https://github.com/vercel-labs/agent-browser/tree/main/skills/agent-browser`
- [ ] User can upload a ZIP containing a skill directory with SKILL.md, references/, templates/
- [ ] Pipeline runs successfully for directory skills
- [ ] Sandbox container has `/workspace/skill` (or configured path) with full file tree
- [ ] Templates (e.g., `templates/form-automation.sh`) are executable in container
- [ ] `SKILL_PATH` environment variable is set in container
- [ ] Existing single-file skills continue to work without changes
- [ ] Parser extracts tools/frameworks/deps from all .md and .sh files in directory
- [ ] DependencyScanner finds package.json/requirements.txt and provides to Analyzer
- [ ] SandboxSpec can specify post_install_commands (e.g., playwright install) for agent-browser

---

## Appendix A: File Tree Format


The `file_tree` map uses **relative paths with forward slashes** as keys. Examples:

```elixir
%{
  "SKILL.md" => "# Agent Browser\n...",
  "references/commands.md" => "# Command Reference\n...",
  "references/authentication.md" => "...",
  "templates/form-automation.sh" => "#!/bin/bash\n..."
}
```

Paths are relative to the skill root. No leading slash. Use `/` for path separators on all platforms.

---

## Appendix B: Agent-Browser Sandbox Requirements

For reference, the agent-browser skill typically needs:

- **Base image:** `node:20-slim` (or similar)
- **System packages:** `git`, `curl`, and Playwright deps (e.g., `libnss3`, `libatk1.0-0`, `libatk-bridge2.0-0`, `libcups2`, `libdrm2`, `libxkbcommon0`, `libxcomposite1`, `libxdamage1`, `libxfixes3`, `libxrandr2`, `libgbm1`, `libasound2`)
- **Runtime deps:** `agent-browser` (and optionally `playwright` for `npx playwright install`)
- **Post-install:** `npx playwright install chromium`

The LLM Analyzer should produce a spec that includes these when given the agent-browser skill.

**Package.json at repo root:** The agent-browser skill directory does not contain `package.json`; it lives at the repo root. Two options:

1. **Option A (recommended):** GitHubFetcher, when fetching a directory, also fetches `package.json` from the repo root if `source_root_url` indicates a subdirectory (e.g., path `skills/agent-browser`). Add it to `file_tree` as `_repo_root/package.json`. DependencyScanner then finds it.
2. **Option B:** Rely on the LLM to infer `agent-browser` from frontmatter (`allowed-tools: Bash(npx agent-browser:*)`) and produce the correct runtime_deps. Simpler but less reliable.

---

## Appendix C: ZIP Extraction (Erlang :zip)

For ZIP upload, use Erlang's built-in `:zip` module:

```elixir
# Extract to temp directory
temp_dir = Path.join(System.tmp_dir!(), "skill_zip_#{:erlang.unique_integer([:positive])}")
File.mkdir_p!(temp_dir)

case :zip.unzip(String.to_charlist(zip_path), [cwd: String.to_charlist(temp_dir)]) do
  {:ok, _file_list} ->
    # Walk temp_dir, validate paths, build file_tree
    # ...
  {:error, reason} ->
    {:error, "ZIP extraction failed: #{inspect(reason)}"}
end

# Cleanup: File.rm_rf!(temp_dir)
```

**Path traversal check:** Before adding a file to `file_tree`, ensure:
```elixir
full_path = Path.join(temp_dir, entry_path)
full_path = Path.expand(full_path)
String.starts_with?(full_path, Path.expand(temp_dir))
```

---

## 13. Gaps Analysis and Resolutions

This section documents gaps identified during plan review and how they are resolved.

| Gap | Resolution |
|-----|------------|
| **Runner parse logic** | Runner's `do_start_parsing` must call `Parser.parse_directory(skill.file_tree)` when `source_type == "directory"`, else `Parser.parse(skill.raw_content)`. Added to §6.10. |
| **Implementation order** | Schema must be updated before backfill (backfill uses `Skill.changeset`). Reordered Phase 1. |
| **Paste mode file_tree** | Paste must set `file_tree: %{"SKILL.md" => content}` so BuildContext always has skill/ to write. Added to §6.11. |
| **GitHub path stripping** | Git Trees API returns full paths. Strip directory prefix to get relative keys. Added to §6.1. |
| **Binary files** | Skip blobs that are invalid UTF-8 or have binary extensions. Added to §6.1. |
| **ZIP path traversal** | Validate extracted paths stay within extraction root. Added to §6.11. |
| **ZIP extraction library** | Use Erlang `:zip` module. Added to §6.11. |
| **ZIP SKILL.md location** | Find SKILL.md, use its dir as root; shallowest wins if multiple. Added to §6.11. |
| **File size limits** | Consider 10MB total, 200 files max for ZIP. Added to §6.11. |
| **DependencyScanner merge** | Prefer Scanner output when present; LLM fills gaps. Added to §6.6. |
| **Package.json at repo root** | Option A: Fetch repo root package.json when path is subdirectory. Added to Appendix B. |
| **Dockerfile skill_mount_path** | Use `spec.skill_mount_path` in COPY dest, chmod path, and ENV SKILL_PATH. Already in §6.9. |
| **BuildContext legacy fallback** | If `file_tree` empty/nil, write `skill/SKILL.md` from `raw_content`. In §8.4. |

---

*End of document.*
