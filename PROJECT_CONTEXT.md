# SkillToSandbox — Project Context & Status Document

> **Generated:** 2026-03-10  
> **App version:** 0.1.0  
> **Status:** Active development — core pipeline functional, no CI configured

---

## Table of Contents

1. [Project Summary](#1-project-summary)
2. [Technology Stack](#2-technology-stack)
3. [Repository Structure](#3-repository-structure)
4. [Architecture Overview](#4-architecture-overview)
5. [Data Model](#5-data-model)
6. [Domain Logic](#6-domain-logic)
   - 6.1 Skills System
   - 6.2 LLM Analysis System
   - 6.3 Pipeline State Machine
   - 6.4 Sandbox & Docker System
   - 6.5 Tools System
7. [Web Layer](#7-web-layer)
   - 7.1 Router & Routes
   - 7.2 LiveViews
   - 7.3 Controllers
   - 7.4 Layouts & Components
8. [Configuration](#8-configuration)
9. [Frontend & Assets](#9-frontend--assets)
10. [OTP Supervision Tree](#10-otp-supervision-tree)
11. [External Integrations](#11-external-integrations)
12. [Test Suite](#12-test-suite)
13. [Development Workflow](#13-development-workflow)
14. [Current Status & Known Gaps](#14-current-status--known-gaps)
15. [Live Experiment Notes](#15-live-experiment-notes)

---

## 1. Project Summary

**SkillToSandbox** is a Phoenix 1.8 web application that automates the conversion of AI agent "skill" definitions into reproducible, tool-equipped Docker sandbox environments.

### Problem it solves

AI agents are defined by `SKILL.md` files (Markdown documents with YAML frontmatter describing the agent's purpose, tools, and dependencies). Running these agents requires matching Docker containers pre-loaded with the right runtimes, packages, and tool scripts. Building these containers manually is tedious and error-prone. SkillToSandbox automates this entire process through an LLM-assisted pipeline.

### End-to-end flow

```
User uploads SKILL.md (or GitHub URL)
        ↓
Parser extracts structure (tools, frameworks, deps)
        ↓
LLM (Claude / GPT-4o) analyzes skill → produces SandboxSpec
        ↓
User reviews and approves the spec
        ↓
Docker image is built from generated Dockerfile
        ↓
Container is launched and monitored in real time
        ↓
Sandbox is ready for AI agent evaluation
```

### Key design choices

- **SQLite** as the database (single-file, no external DB server)
- **No authentication** — intended as an internal research tool
- **Real-time UI** via Phoenix LiveView with PubSub
- **Req** as the sole HTTP client throughout
- **Docker CLI** (not the Docker API) for container operations
- Containers **never hold API keys** — they call back to the host Phoenix app at `/api/tools/search` for web search, which proxies to Tavily

---

## 2. Technology Stack

### Language & Runtime

| Component | Version |
|---|---|
| Elixir | `~> 1.15` |
| OTP | standard (`extra_applications: [:logger, :runtime_tools]`) |
| Phoenix | `1.8.3` (locked) |
| Phoenix LiveView | `1.1.22` (locked) |
| Bandit (HTTP server) | `1.10.2` (locked, replaces Cowboy) |

### Core Dependencies

| Package | Locked Version | Purpose |
|---|---|---|
| `phoenix` | 1.8.3 | Web framework |
| `phoenix_ecto` | (latest) | Ecto ↔ Phoenix form integration |
| `ecto_sql` | 3.13.4 | SQL query layer |
| `ecto_sqlite3` | 0.22.0 | SQLite3 Ecto adapter |
| `exqlite` | 0.34.0 | SQLite NIF driver |
| `phoenix_live_view` | 1.1.22 | Real-time server-rendered UI |
| `phoenix_live_dashboard` | 0.8.7 | Dev metrics dashboard |
| `req` | 0.5.17 | HTTP client (used everywhere) |
| `swoosh` | 1.21.0 | Email (local mailbox in dev) |
| `earmark` | 1.4.48 | Markdown → HTML rendering |
| `yaml_elixir` | 2.12.0 | YAML parsing (SKILL.md frontmatter) |
| `jason` | 1.4.4 | JSON encoding/decoding |
| `dns_cluster` | 0.2.0 | Distributed Elixir support |
| `telemetry_metrics` | 1.1.0 | Metrics aggregation |
| `telemetry_poller` | 1.3.0 | Periodic metric polling |
| `gettext` | 1.0.2 | Internationalization |
| `heroicons` | v2.2.0 (sparse) | SVG icons |
| `esbuild` | 0.10.0 (dev) | JS bundler |
| `tailwind` | 0.4.1 (dev) | Tailwind CSS CLI runner |
| `lazy_html` | 0.1.10 (test) | HTML assertions in tests |
| `bypass` | 2.1.0 (test) | HTTP mock server for tests |

### Frontend

- **Tailwind CSS v4** (new import syntax, no `tailwind.config.js`)
- **DaisyUI** component library (Tailwind plugin, themes disabled by plugin — defined manually)
- **Heroicons v2.2.0** via Tailwind plugin
- Custom CSS utilities: `.bg-mesh`, `.glass-panel`, `.glow-primary`, `.glow-accent`
- **Topbar.js** — navigation progress bar
- One custom JS hook: `AutoScroll` (log viewer)

---

## 3. Repository Structure

```
SubAgentResearch/
├── mix.exs                         # Project definition, deps, aliases
├── mix.lock                        # Pinned dependency versions
├── README.md                       # Boilerplate Phoenix quickstart (not project-specific)
├── AGENTS.md                       # AI coding guidelines for this repo
├── PROJECT_CONTEXT.md              # This document
├── skill_to_sandbox_dev.db         # SQLite dev database (runtime artifact)
├── skill_to_sandbox_test.db        # SQLite test database (runtime artifact)
├── erl_crash.dump                  # Erlang crash dump (runtime artifact)
│
├── config/
│   ├── config.exs                  # Base config (endpoint, Ecto, mailer, esbuild, tailwind)
│   ├── dev.exs                     # Dev: DB path, watchers, LiveReload, debug flags
│   ├── prod.exs                    # Prod: SSL, static manifest, Swoosh
│   ├── runtime.exs                 # Runtime env-var config (LLM, search, DB, PORT)
│   └── test.exs                    # Test: in-memory/file DB, sandbox mode
│
├── lib/
│   ├── skill_to_sandbox.ex         # Top-level context facade (unused, Phoenix placeholder)
│   ├── skill_to_sandbox_web.ex     # Phoenix web helper macros
│   ├── skill_to_sandbox/
│   │   ├── application.ex          # OTP Application / supervision tree
│   │   ├── repo.ex                 # Ecto Repo (SQLite3 adapter)
│   │   ├── mailer.ex               # Swoosh mailer
│   │   │
│   │   ├── skills/                 # Skills domain
│   │   │   ├── skill.ex            # Ecto schema
│   │   │   ├── parser.ex           # SKILL.md parser (YAML frontmatter + keyword analysis)
│   │   │   ├── git_hub_fetcher.ex  # Fetch skills from GitHub (file or directory)
│   │   │   ├── dependency_scanner.ex   # Scan package.json / requirements.txt / pyproject.toml
│   │   │   ├── canonical_deps.ex   # Human name → canonical npm/pip package name map
│   │   │   └── package_validator.ex    # Validate packages against npm/PyPI registries
│   │   ├── skills.ex               # Skills context (CRUD + queries)
│   │   │
│   │   ├── analysis/               # LLM analysis domain
│   │   │   ├── sandbox_spec.ex     # Ecto schema for sandbox specifications
│   │   │   ├── analyzer.ex         # Orchestrates LLM analysis, prompt building, validation
│   │   │   ├── llm_client.ex       # HTTP client for OpenAI / Anthropic APIs
│   │   │   ├── code_dependency_extractor.ex  # Extract deps from code (imports, CDN URLs)
│   │   │   ├── dependency_relevant_files.ex  # Select files for LLM (70k char budget)
│   │   │   └── json_data.ex        # Custom Ecto type for JSON arrays
│   │   ├── analysis.ex             # Analysis context (SandboxSpec CRUD)
│   │   │
│   │   ├── pipeline/               # Pipeline orchestration
│   │   │   ├── pipeline_run.ex     # Ecto schema for pipeline run state
│   │   │   ├── runner.ex           # GenServer state machine for one pipeline run
│   │   │   ├── supervisor.ex       # DynamicSupervisor for Runner processes
│   │   │   └── recovery.ex         # Restart interrupted runs on boot
│   │   ├── pipelines.ex            # Pipelines context (PipelineRun CRUD)
│   │   │
│   │   ├── sandbox/                # Docker sandbox domain
│   │   │   ├── sandbox.ex          # Ecto schema for running containers
│   │   │   ├── build_context.ex    # Assemble Dockerfile + context directory
│   │   │   ├── dockerfile_builder.ex   # Generate Dockerfile from SandboxSpec
│   │   │   ├── docker.ex           # Wrapper around Docker CLI commands
│   │   │   ├── docker_check.ex     # Check if Docker daemon is available
│   │   │   ├── monitor.ex          # GenServer: stream logs + health poll per container
│   │   │   └── manifest.ex         # Generate tool_manifest.json for containers
│   │   ├── sandboxes.ex            # Sandboxes context (CRUD + queries)
│   │   │
│   │   ├── tools/                  # Tool implementations (CLI execution, web search)
│   │   │   ├── tool.ex             # Behaviour: name, description, parameter_schema, execute
│   │   │   ├── cli.ex              # CLI execution tool (runs bash in containers)
│   │   │   └── web_search.ex       # Web search via Tavily (proxied from containers)
│   │   │
│   │   ├── agent/                  # Agent loop orchestration
│   │   │   ├── runner.ex           # LLM→bash agent loop with DONE/STUCK signals, step logging
│   │   │   └── prompt_builder.ex   # Skill-aware system prompt construction from allowed-tools
│   │   │
│   │   └── ecto_types/
│   │       └── json_data.ex        # Custom Ecto type (map/list stored as JSON text)
│   │
│   └── skill_to_sandbox_web/
│       ├── endpoint.ex             # Phoenix Endpoint (plugs, session, WebSocket)
│       ├── router.ex               # Route definitions
│       ├── gettext.ex              # Gettext backend
│       ├── telemetry.ex            # Telemetry supervisor + metrics
│       ├── components/
│       │   ├── core_components.ex  # Shared UI: flash, button, input, table, icon
│       │   ├── layouts.ex          # App/root layout components
│       │   └── layouts/
│       │       └── root.html.heex  # Root HTML shell
│       ├── controllers/
│       │   ├── page_controller.ex  # Vestigial (no route maps to it)
│       │   ├── error_html.ex       # HTML error pages
│       │   ├── error_json.ex       # JSON error responses
│       │   └── api/
│       │       └── tool_controller.ex  # POST /api/tools/search (container proxy)
│       └── live/
│           ├── dashboard_live.ex       # / — stats overview
│           ├── skill_live/
│           │   ├── index.ex            # /skills — list
│           │   ├── new.ex              # /skills/new — upload
│           │   └── show.ex             # /skills/:id — detail + run pipeline
│           ├── pipeline_live/
│           │   └── show.ex             # /skills/:id/pipeline — real-time progress
│           └── sandbox_live/
│               ├── index.ex            # /sandboxes — list
│               └── show.ex             # /sandboxes/:id — logs + controls
│
├── assets/
│   ├── css/app.css                 # Tailwind v4 + DaisyUI + custom utilities
│   ├── js/app.js                   # LiveSocket, AutoScroll hook, topbar
│   ├── vendor/
│   │   ├── topbar.js               # Navigation progress bar
│   │   ├── heroicons.js            # Tailwind plugin for Heroicons
│   │   ├── daisyui.js              # DaisyUI Tailwind plugin
│   │   └── daisyui-theme.js        # DaisyUI theme plugin
│   └── tsconfig.json               # TypeScript config (for esbuild)
│
├── priv/
│   ├── repo/
│   │   ├── migrations/             # 6 Ecto migration files (2026-02-11 + 2026-02-24)
│   │   └── seeds.exs               # Seeds one sample "frontend-design" skill
│   ├── static/                     # Built asset output (css/app.css, js/app.js)
│   └── gettext/                    # Translation .po/.pot files
│
└── test/
    ├── test_helper.exs
    ├── support/                    # Test case helpers
    ├── fixtures/
    │   └── frontend_design_skill.md  # Real-world fixture used by parser tests
    ├── skill_to_sandbox/
    │   ├── skills/                 # Parser, fetcher, validator, scanner, canonical deps
    │   ├── analysis/               # Analyzer, code extractor, relevant files
    │   ├── pipeline/               # Runner and recovery
    │   ├── sandbox/                # BuildContext, DockerfileBuilder
    │   ├── agent/                      # Runner strip_command, PromptBuilder build
    │   └── integration/            # End-to-end pipeline + dependency detection
    └── skill_to_sandbox_web/
        └── controllers/            # API controller tests
```

---

## 4. Architecture Overview

The application is built around three major asynchronous domains that communicate through the database and PubSub:

```
┌─────────────────────────────────────────────────────────────────────┐
│                         Phoenix LiveView UI                          │
│  DashboardLive  SkillLive  PipelineLive  SandboxLive                │
│         │              │         │              │                    │
│         └──────────────┴────PubSub Bus──────────┘                  │
└───────────────────────────────┬─────────────────────────────────────┘
                                │ PubSub
        ┌───────────────────────┼───────────────────────┐
        ▼                       ▼                       ▼
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ Pipeline     │     │   TaskSupervisor  │     │  SandboxMonitor   │
│ Runner       │────▶│  (LLM calls,      │     │  (log streaming, │
│ (GenServer)  │     │   Docker builds)  │     │   health polls)  │
└──────┬───────┘     └──────────────────┘     └────────┬─────────┘
       │                                               │
       ▼                                               ▼
┌──────────────────────────────────────────────────────────────────┐
│                    SQLite Database (Ecto)                         │
│  skills  │  sandbox_specs  │  sandboxes  │  pipeline_runs        │
└──────────────────────────────────────────────────────────────────┘
       │
       ▼ shell exec
┌──────────────┐    ┌────────────────────────────────┐
│ Docker CLI   │───▶│  Running Containers             │
│ (System.cmd) │    │  • /workspace/skill/            │
└──────────────┘    │  • /tools/*.sh                  │
                    │  • /workspace/tool_manifest.json │
                    └──────────┬─────────────────────┘
                               │ HTTP POST
                    ┌──────────▼─────────────────────┐
                    │  Host: POST /api/tools/search   │
                    │  (Tavily web search proxy)       │
                    └─────────────────────────────────┘
```

---

## 5. Data Model

### Entity Relationships

```
skills (1) ──────────────────────── (many) sandbox_specs
  │                                            │
  │ (1)                                        │ (1)
  │                                            │ (many)
  └───── (many) pipeline_runs ─────────────── sandboxes
                 │
                 ├── belongs_to skill
                 ├── belongs_to sandbox_spec (nullable)
                 └── belongs_to sandbox (nullable)
```

**Foreign key behavior:**
- `skill` deleted → all `sandbox_specs` and `pipeline_runs` cascade-deleted at DB level
- `skill` deleted → all `sandboxes` for those specs must be deleted first (app-level transaction in `Skills.delete_skill/1`) because `sandboxes.sandbox_spec_id` is NOT NULL but the DB ON DELETE action is NILIFY ALL (a schema tension)
- `sandbox_spec` deleted → `sandboxes.sandbox_spec_id` and `pipeline_runs.sandbox_spec_id` nilified
- `sandbox` deleted → `pipeline_runs.sandbox_id` nilified

### Table: `skills`

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | integer | PK | |
| `name` | string | NOT NULL | |
| `description` | text | nullable | |
| `source_url` | string | nullable | URL of original skill file |
| `raw_content` | text | NOT NULL | Raw Markdown |
| `parsed_data` | map/JSON | default `{}` | Output from Parser |
| `source_type` | string | NOT NULL, default `"file"` | `"file"` or `"directory"` |
| `source_root_url` | string | nullable | Root URL for directory-type skills |
| `file_tree` | map/JSON | default `{}` | `path → content` for directories |
| `inserted_at` | utc_datetime | NOT NULL | |
| `updated_at` | utc_datetime | NOT NULL | |

### Table: `sandbox_specs`

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | integer | PK | |
| `skill_id` | integer | NOT NULL, FK → skills CASCADE | |
| `base_image` | string | NOT NULL | e.g. `"node:20-slim"` |
| `system_packages` | map/JSON | default `{}` | List of apt package names |
| `runtime_deps` | map/JSON | default `{}` | `{manager, packages}` |
| `tool_configs` | map/JSON | default `{}` | CLI + web_search config |
| `eval_goals` | map/JSON | default `{}` | List of evaluation goal strings |
| `dockerfile_content` | text | nullable | Generated Dockerfile text |
| `status` | string | NOT NULL, default `"draft"` | `draft/approved/building/built/failed` |
| `skill_mount_path` | string | default `"/workspace/skill"` | |
| `post_install_commands` | map/JSON | default `[]` | e.g. `npx playwright install chromium` |

### Table: `sandboxes`

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | integer | PK | |
| `sandbox_spec_id` | integer | NOT NULL, FK → sandbox_specs NILIFY | |
| `container_id` | string | nullable | Docker container ID |
| `image_id` | string | nullable | Docker image tag |
| `status` | string | NOT NULL, default `"building"` | `building/running/stopped/error` |
| `port_mappings` | map/JSON | default `{}` | Docker port mappings (not currently populated) |
| `error_message` | text | nullable | |

### Table: `pipeline_runs`

| Column | Type | Constraints | Notes |
|---|---|---|---|
| `id` | integer | PK | |
| `skill_id` | integer | NOT NULL, FK → skills CASCADE | |
| `sandbox_spec_id` | integer | nullable, FK → sandbox_specs NILIFY | Set after analysis |
| `sandbox_id` | integer | nullable, FK → sandboxes NILIFY | Set after build |
| `status` | string | NOT NULL, default `"pending"` | Full state machine |
| `current_step` | integer | default `0` | Numeric step (0–6, -1 for failed) |
| `error_message` | text | nullable | |
| `started_at` | utc_datetime | nullable | |
| `completed_at` | utc_datetime | nullable | Set on `ready` or `failed` |
| `step_timings` | map/JSON | default `{}` | `step_name → elapsed_ms` |

### Pipeline Run Status Values & Step Numbers

| Status | Step # | Description |
|---|---|---|
| `pending` | 0 | Run created, not yet started |
| `parsing` | 1 | Extracting structure from SKILL.md |
| `analyzing` | 2 | LLM generating SandboxSpec |
| `reviewing` | 3 | Awaiting user approval |
| `building` | 4 | Docker image being built |
| `configuring` | 5 | Verifying container setup |
| `ready` | 6 | Container is live and verified |
| `failed` | -1 | Terminal error state |

### Custom Ecto Type: `JsonData`

`SkillToSandbox.EctoTypes.JsonData` extends `:map` to also accept lists. Used for `system_packages`, `eval_goals`, and `post_install_commands` in `SandboxSpec`, since these are arrays at the application layer but stored as JSON text in SQLite.

---

## 6. Domain Logic

### 6.1 Skills System

**Context:** `SkillToSandbox.Skills`

| Function | Description |
|---|---|
| `list_skills/0` | All skills, `inserted_at DESC` |
| `get_skill!/1` | Raises if not found |
| `create_skill/1` | Via changeset |
| `update_skill/2` | Via changeset |
| `delete_skill/1` | Transaction: deletes sandboxes first, then skill (cascade-deletes specs + runs) |
| `change_skill/2` | For form tracking |
| `count_skills/0` | Aggregate count |

**Schema:** `SkillToSandbox.Skills.Skill`
- Required fields: `name`, `raw_content`
- Validates `source_type` is `"file"` or `"directory"`
- When `source_type == "directory"`, `file_tree` must be a non-empty map

#### Parser (`SkillToSandbox.Skills.Parser`)

Three-stage operation:

1. **Frontmatter extraction** — Splits on `---` delimiters, parses YAML with `YamlElixir`. Gracefully falls back if no frontmatter.
2. **Keyword analysis** — Regex-based detection of:
   - Tools: `web_search`, `file_write`, `file_read`, `browser`, `cli_execution`, `code_execution`
   - Frameworks: React, Vue, Angular, Python, Django, Flask, Express, Next.js, Svelte, etc.
   - Dependencies: Framer Motion, Tailwind CSS, Axios, Redux, etc.
   - Note: Express.js requires technical context (e.g. `require('express')`) to avoid false positives from the English word "express"
3. **Assembly** — Returns a map with `name`, `description`, `sections`, `mentioned_tools`, `mentioned_frameworks`, `mentioned_dependencies`, `raw_guidelines`, `frontmatter`

`parse_directory/1` — runs the same analysis across all `.md` and `.sh` files in a `file_tree`, merging results, using `SKILL.md` as the primary source for frontmatter.

`extract_allowed_tools_deps/1` — extracts npm package names from `allowed-tools` frontmatter (handles patterns like `Bash(npx agent-browser:*)`).

#### GitHub Fetcher (`SkillToSandbox.Skills.GitHubFetcher`)

- `github.com/.../blob/.../SKILL.md` → fetches raw content via `raw.githubusercontent.com`
- `github.com/.../tree/...` → uses GitHub Git Trees API (`/repos/{owner}/{repo}/git/trees/{sha}?recursive=1`), then concurrently fetches all text blobs (`Task.async_stream/3`, `max_concurrency: 5`)
- For subdirectory fetches, also attempts to fetch repo-root `package.json`, `requirements.txt`, `pyproject.toml` (stored under `_repo_root/` keys)
- Optional `GITHUB_TOKEN` env var for higher API rate limits
- Skips binary-extension files and invalid UTF-8

#### Dependency Scanner (`SkillToSandbox.Skills.DependencyScanner`)

Scans `file_tree` for dependency manifests:
- `package.json` — parses `dependencies` + `devDependencies`; merges multiple files (shallowest path wins)
- `requirements.txt` — pip-style parsing; handles `-r` recursive includes; skips `-e` and `-c`
- `pyproject.toml` — parses `[project] dependencies` (PEP 621)

#### Package Validator (`SkillToSandbox.Skills.PackageValidator`)

Validates LLM-suggested packages against live registries (configurable: `validate_packages: true`):
- npm: `GET https://registry.npmjs.org/<pkg>/latest` — 200 = valid
- PyPI: `GET https://pypi.org/pypi/<normalized>/json` — 200 = valid
- Concurrent: `Task.async_stream/3`, `max_concurrency: 5`
- Strips invalid packages from spec; skipped when manifest files already present

#### Canonical Deps (`SkillToSandbox.Skills.CanonicalDeps`)

Maps human-readable names from the Parser (e.g. `"Framer Motion"`) to canonical package names (e.g. `"framer-motion"`). Used to give the LLM correct names when no manifest files are present.

---

### 6.2 LLM Analysis System

**Context:** `SkillToSandbox.Analysis`

| Function | Description |
|---|---|
| `create_spec/1` | Create a SandboxSpec |
| `get_spec!/1` | Raises if not found |
| `update_spec/2` | Update a SandboxSpec |
| `approve_spec/1` | Sets `status: "approved"` |
| `specs_for_skill/1` | All specs for a skill, `inserted_at DESC` |

#### Analyzer (`SkillToSandbox.Analysis.Analyzer`)

Orchestrates the full LLM analysis pipeline on a `%Skill{}`:

1. `DependencyScanner.scan(skill.file_tree)` — scan manifest files
2. `CodeDependencyExtractor.extract_all(skill.file_tree)` — extract imports + CDN URLs from code
3. Build prompt from skill content + scanner + extracted deps
4. `LLMClient.chat(system_prompt, user_prompt)` — call LLM with retry logic
5. `extract_json/1` — parse JSON from response (strips markdown fences)
6. `validate_spec/1` — validate required fields and types
7. `merge_scanner_deps/2` — manifest deps override LLM for conflicts
8. `merge_extracted_deps/2` — CDN/import deps override LLM for conflicts
9. `ensure_react_dom/1` — auto-adds `react-dom` when `react` is present
10. `ensure_allowed_tools/2` — adds `allowed-tools` frontmatter npx packages to runtime deps
11. `maybe_validate_packages/2` — calls PackageValidator (skipped when manifests present)
12. `Analysis.create_spec/1` — persists as `SandboxSpec` with `status: "draft"`

**Expected JSON structure from LLM:**
```json
{
  "base_image": "node:20-slim",
  "system_packages": ["git", "curl"],
  "runtime_deps": {
    "manager": "npm",
    "packages": { "react": "^18.0.0", "react-dom": "^18.0.0" }
  },
  "tool_configs": {
    "cli": { "shell": "bash", "working_dir": "/workspace", "path_additions": [], "timeout_seconds": 30 },
    "web_search": { "enabled": true, "description": "..." }
  },
  "eval_goals": ["Goal 1", "Goal 2", ...],
  "post_install_commands": ["npx playwright install chromium"],
  "skill_mount_path": "/workspace/skill"
}
```

**Validation rules:** `base_image` non-empty string; `system_packages` list of strings; `runtime_deps` has manager + packages map; `tool_configs` has cli + web_search maps; `eval_goals` minimum 5 strings.

#### LLM Client (`SkillToSandbox.Analysis.LLMClient`)

- **Providers:** `"anthropic"` (Claude) and `"openai"` (GPT)
- **Default models:** `claude-sonnet-4-20250514` (Anthropic), `gpt-4o` (OpenAI)
- **Retry:** Up to 3 attempts with exponential backoff (1s base) for server errors + timeouts; respects `Retry-After` header for rate limits
- **Timeout:** 120 seconds per request
- **Test stub:** Provider `"test"` returns a minimal valid spec without any API call (used in all unit/integration tests)
- Configured via `config :skill_to_sandbox, :llm` — `provider`, `api_key`, `model`

#### Code Dependency Extractor (`SkillToSandbox.Analysis.CodeDependencyExtractor`)

Deterministically extracts packages from file contents:
- **CDN URLs** in `<script src="...">`: Handles cdnjs, unpkg, jsdelivr; maps CDN names to npm names; preserves version from URL
- **JS/TS imports:** `require('pkg')`, `import x from 'pkg'`; skips relative paths and Node built-ins
- **Python imports:** `import foo`, `from foo.bar import`; skips stdlib modules

#### Dependency Relevant Files (`SkillToSandbox.Analysis.DependencyRelevantFiles`)

Selects files to send to LLM within a 70,000-character budget:
1. Manifest files (full content, never truncated)
2. Files containing import/require patterns
3. Other code/HTML files (truncated to 5,000 chars)

Excludes: `node_modules/`, `vendor/`, `dist/`, `build/`, license files.

---

### 6.3 Pipeline State Machine

**Module:** `SkillToSandbox.Pipeline.Runner` (GenServer)

```
pending → parsing → analyzing → reviewing → building → configuring → ready
                                                                   ↘ failed
```

Every state transition:
1. Calls `Pipelines.update_run/2` (DB persistence with step number + timestamp)
2. Broadcasts `{:pipeline_update, payload}` on PubSub topic `"pipeline:<run_id>"`

Heavy operations are offloaded via `Task.Supervisor.async_nolink/2` under `SkillToSandbox.TaskSupervisor`. Results arrive as `handle_info({ref, result}, ...)` messages.

**Step implementations:**
- `parsing` — Synchronous. `Parser.parse/1` or `Parser.parse_directory/1`. Updates `skill.parsed_data` in DB if not set.
- `analyzing` — Async. `Analyzer.analyze(skill)` → creates `SandboxSpec` record.
- `reviewing` — Pause state. Waits for `cast(:approve_spec, ...)` or `cast(:re_analyze, ...)`.
- `building` — Async, `timeout: :infinity`. Assembles build context dir → `docker build` → `docker run -d` → creates `Sandbox` DB record.
- `configuring` — Async. Runs `docker exec <id> "test -f /workspace/tool_manifest.json && echo OK"` to verify container.
- `ready` — Starts a `Monitor` GenServer for the sandbox, then the Runner process terminates normally.

**Public API:**
- `Runner.approve_spec(run_id)` — cast; only valid in `reviewing`
- `Runner.re_analyze(run_id)` — cast; only valid in `reviewing`
- `Runner.retry(run_id)` — cast; only valid in `failed`
- `Runner.get_status(run_id)` — synchronous call
- `Runner.alive?(run_id)` — checks `PipelineRegistry`

**Process registration:** `{:via, Registry, {SkillToSandbox.PipelineRegistry, run_id}}`

**Supervisor:** `SkillToSandbox.Pipeline.Supervisor` (DynamicSupervisor)
- `start_pipeline(skill_id)` — creates DB record, starts `Runner` child
- `resume_pipeline(run_id, skill_id)` — starts `Runner` with `resume: true` mode

**Recovery:** `SkillToSandbox.Pipeline.Recovery` runs as a startup `Task` (1-second delay):
- `reviewing`, `pending`, `parsing`, `analyzing` → resume (restart Runner in resume mode)
- `building`, `configuring` → mark as `failed` with message "Interrupted by application restart"

---

### 6.4 Sandbox & Docker System

**Context:** `SkillToSandbox.Sandboxes`

| Function | Description |
|---|---|
| `list_sandboxes/0` | All sandboxes `DESC`, preloads `sandbox_spec: :skill` |
| `get_sandbox/1` | Returns nil if not found; preloads associations |
| `get_sandbox!/1` | Raises if not found; preloads associations |
| `create_sandbox/1` | Via changeset |
| `update_sandbox/2` | Via changeset |
| `delete_sandbox/1` | Via changeset |
| `delete_sandboxes_for_spec_ids/1` | Bulk delete by `sandbox_spec_id` |
| `sandboxes_for_spec/1` | Filtered list, `DESC` |
| `count_sandboxes/0` | Total count |
| `count_sandboxes_by_status/1` | Count for a given status string |

#### Docker Wrapper (`SkillToSandbox.Sandbox.Docker`)

All operations use `System.cmd("docker", ...)` wrapped in `Task.async/1` + `Task.yield/2` + `Task.shutdown/2` for timeout enforcement.

| Function | Docker Command | Timeout |
|---|---|---|
| `build_image/3` | `docker build -t <tag> <context>` | 300s |
| `run_container/3` | `docker run -d --name <name> --memory=2g --cpus=2 <image>` | 60s |
| `exec_in_container/3` | `docker exec <id> /bin/bash -c <cmd>` | 30s |
| `stop_container/1` | `docker stop <id>` | 30s |
| `remove_container/1` | `docker rm -f <id>` | 30s |
| `restart_container/1` | `docker restart <id>` | 30s |
| `container_status/1` | `docker inspect --format {{.State.Status}} <id>` | 30s |
| `stream_logs/1` | Erlang Port: `docker logs --follow --tail 100 <id>` | — |

Linux gets `--add-host=host.docker.internal:host-gateway` for host-to-container communication.

#### Build Context (`SkillToSandbox.Sandbox.BuildContext`)

Assembles a temp directory in `System.tmp_dir!()`:
1. `Dockerfile` — from `DockerfileBuilder.build(spec)`
2. `package.json` or `requirements.txt` — from `spec.runtime_deps`
3. `tools/` — shell scripts: `cli_execution.sh`, `web_search.sh`
4. `tool_manifest.json` — from `Manifest.generate/0`
5. `skill/` — full `file_tree` (directory skills) or just `SKILL.md` (single-file skills)

#### Dockerfile Builder (`SkillToSandbox.Sandbox.DockerfileBuilder`)

Generates Dockerfile sections in order:
1. `FROM <base_image>` + `LABEL skill_id=<id>`
2. `RUN apt-get install -y <system_packages>`
3. `WORKDIR /workspace`
4. Package install: `COPY package.json` + `RUN npm install --omit=dev --legacy-peer-deps` (npm), or `COPY requirements.txt` + `RUN pip install -r requirements.txt` (pip)
5. `post_install_commands` (e.g. `npx playwright install chromium`)
6. `COPY tools/ /tools/` + `ENV PATH="/tools:$PATH"` + `COPY tool_manifest.json /workspace/`
7. `COPY skill/ <skill_mount_path>/`
8. Env vars: `WORKSPACE_DIR`, `CLI_TIMEOUT`, `SKILL_PATH`
9. `CMD ["tail", "-f", "/dev/null"]` — keeps container alive for `docker exec`

#### Sandbox Monitor (`SkillToSandbox.Sandbox.Monitor`)

GenServer registered via `{:via, Registry, {SkillToSandbox.SandboxRegistry, sandbox_id}}`. Restart strategy: `:temporary` (no automatic restart on crash).

Responsibilities:
- **Log streaming:** Opens a Docker `Port` (`docker logs --follow --tail 100 <id>`). Buffers last 500 lines. Broadcasts each line to `"sandbox:<id>"` as `{:log_line, line}`.
- **Health polling:** Every 5s runs `Docker.container_status/1`. On change, updates Sandbox DB record and broadcasts to both `"sandbox:<id>"` and `"sandboxes:updates"`.
- **Container control:** `stop_container/1`, `restart_container/1`, `destroy_container/1` — closes log port, executes Docker command, updates DB, broadcasts.

Status normalization: Docker's `"exited"` → `"stopped"`, `"created"` → `"building"`, `"dead"` → `"error"`, `"removing"` → `"stopped"`.

---

### 6.5 Tools System

**Behaviour:** `SkillToSandbox.Tools.Tool`

Callbacks: `name/0`, `description/0`, `parameter_schema/0` (JSON Schema), `execute/1`, `container_setup_script/0`.

#### CLI Tool (`SkillToSandbox.Tools.CLI`)

- Executes shell commands inside a container via `Docker.exec_in_container/3`
- Parameters: `command` (required), `container_id` (required), `working_dir` (optional)
- Shell script in container: `timeout "$TIMEOUT" bash -c "$*"` with `CLI_TIMEOUT` env var
- Configurable timeout: `CLI_TIMEOUT_MS` env var (default 30000ms)

#### Web Search Tool (`SkillToSandbox.Tools.WebSearch`)

- Executes searches via Tavily API (`https://api.tavily.com/search`)
- Parameters: `query` (required), `max_results` (optional, default 5)
- Shell script in container calls **host app** via `curl http://host.docker.internal:<PORT>/api/tools/search` — containers never hold API keys
- Only `"tavily"` provider is fully implemented
- Configurable via `config :skill_to_sandbox, :search` — `provider`, `api_key`

#### Tool Manifest (`SkillToSandbox.Sandbox.Manifest`)

Generates `/workspace/tool_manifest.json` inside the container with:
- `version`, `generated_at`
- Tool list: `name`, `description`, `parameter_schema` (JSON Schema), `invocation_type: "shell_script"`, `script_path: "/tools/<name>.sh"`

---

### 6.6 Agent System

**Modules:** `SkillToSandbox.Agent.Runner`, `SkillToSandbox.Agent.PromptBuilder`

The agent system drives an LLM in a step-by-step bash loop inside a running sandbox container. Each step: send context to LLM → parse command → execute in container → accumulate output → repeat.

#### Runner (`SkillToSandbox.Agent.Runner`)

**Public API:**

| Function | Description |
|---|---|
| `run/3` | Run an agent loop. Args: `task` (string), `container_id` (string), `opts` (keyword). Returns `{:ok, :done, steps}`, `{:error, :stuck, steps}`, `{:error, :step_limit, steps}`, or `{:error, reason}` |
| `strip_command/1` | Strip markdown fences and leading `$` shell prompt prefix from LLM output |

**Options for `run/3`:**
- `:max_steps` — integer, default 12
- `:system_prompt` — override the default system prompt
- `:preflight` — boolean (default `true`); runs `echo preflight_ok` before the loop to verify container is live

**Termination signals:**
- `DONE` — LLM confirms task complete; loop halts with `{:ok, :done, steps}`
- `STUCK` — LLM declares task impossible; loop halts with `{:error, :stuck, steps}`
- Step limit exhausted → `{:error, :step_limit, steps}`

**Step map structure** (accumulated in `steps` list):
```elixir
%{
  step: integer,        # 1-based step number
  command: String.t(),  # the stripped bash command that was executed
  output: String.t(),   # stdout+stderr from the container (truncated to 1000 chars)
  elapsed_ms: integer,  # time taken for CLI.execute
  status: :ok | :error  # whether CLI.execute succeeded
}
```

**Key design decisions:**
- Context history uses `"Command: #{command}"` (NOT `"$ #{command}"`) — the `$` prefix was found to pattern-teach the LLM to include `$` in its output, causing bash failures (see Section 15)
- `strip_command/1` strips both markdown fences AND leading `$ ` — defense-in-depth against LLM formatting habits
- System prompt includes explicit self-correction instruction: "if your previous command produced an error, analyze the error and try a DIFFERENT approach"
- Each command is piped through `| tee /proc/1/fd/1` so output appears live in the sandbox log viewer
- Pre-flight check (`echo preflight_ok`) verifies the container is reachable before starting the loop

#### PromptBuilder (`SkillToSandbox.Agent.PromptBuilder`)

**`build/1`** — takes `skill.parsed_data` (map) and returns a system prompt string.

If `parsed_data["frontmatter"]["allowed-tools"]` is present, appends an explicit invocation guide for each tool extracted from the frontmatter. For example, `Bash(npx agent-browser:*)` becomes:
```
This skill's tools (use these exact invocation styles):
  - agent-browser → invoke as: npx agent-browser <subcommand>
```

The `npx` prefix is preserved when present in the frontmatter — solving the root cause of the March 10 experiment failure where the LLM tried bare `agent-browser` instead of `npx agent-browser` (see Section 15).

---

## 7. Web Layer

### 7.1 Router & Routes

**No authentication** — all routes are publicly accessible.

#### Browser routes (pipeline `:browser`)

| Path | LiveView | Action |
|---|---|---|
| `/` | `DashboardLive` | `:index` — system stats + Docker status |
| `/skills` | `SkillLive.Index` | `:index` — list all skills |
| `/skills/new` | `SkillLive.New` | `:new` — upload/paste/GitHub URL form |
| `/skills/:id` | `SkillLive.Show` | `:show` — skill detail + run pipeline |
| `/skills/:id/pipeline` | `PipelineLive.Show` | `:show` — real-time pipeline progress |
| `/sandboxes` | `SandboxLive.Index` | `:index` — list all sandboxes |
| `/sandboxes/:id` | `SandboxLive.Show` | `:show` — container logs + controls |

#### API routes (pipeline `:api`)

| Method | Path | Controller | Action |
|---|---|---|---|
| `POST` | `/api/tools/search` | `API.ToolController` | `:search` — web search proxy for containers |

#### Dev-only routes (`/dev`)

| Path | Handler |
|---|---|
| `/dev/dashboard` | `Phoenix.LiveDashboard` |
| `/dev/mailbox` | `Plug.Swoosh.MailboxPreview` |

### 7.2 LiveViews

#### `DashboardLive` (`/`)

Read-only stats overview. Assigns: `skill_count`, `sandbox_count`, `running_sandbox_count`, `active_pipeline_count`, `docker_available`, `docker_version`. No event handlers. UI: hero panel with CTAs, 4-card stats grid, Docker status card, 3-step "How it works" guide.

#### `SkillLive.Index` (`/skills`)

Skills table. Event: `"delete"` — calls `Skills.delete_skill/1`, re-assigns skills list. Empty state with CTA.

#### `SkillLive.New` (`/skills/new`)

Upload form with 3 modes (tab switcher):
- **Paste** — raw Markdown pasted in textarea
- **File Upload** — `.md` (direct parse) or `.zip` (extract + tree-parse); max 10MB, 200 files
- **GitHub URL** — accepts `github.com/.../blob/...` and `github.com/.../tree/...`

Events: `"switch_mode"`, `"validate"` (real-time form sync), `"save_paste"`, `"save_upload"`, `"save_url"`. GitHub fetch is async (sets `:fetching` boolean, sends `{:fetch_url, ...}` to self). ZIP extraction is path-traversal-safe.

#### `SkillLive.Show` (`/skills/:id`)

Skill detail with parsed analysis display. Events: `"analyze"` (starts pipeline → navigates to `/skills/:id/pipeline`), `"delete"`. Shows tag clouds for tools/frameworks/dependencies/sections, frontmatter key-value grid, raw content panel.

#### `PipelineLive.Show` (`/skills/:id/pipeline`)

Real-time pipeline progress. Subscribes to `"pipeline:<run_id>"`. Handles `{:pipeline_update, payload}`.

Events: `"update_spec"`, `"approve_spec"`, `"re_analyze"`, `"retry"`, `"add_eval_goal"`, `"remove_eval_goal"`, `"update_eval_goal"`, `"add_package"`, `"remove_package"`, `"remove_runtime_dep"`, `"add_runtime_dep"`.

UI: 6-step progress indicator → in `reviewing`: full editable spec form → in `building`/`configuring`: spinner → in `ready`: success + sandbox link → in `failed`: error + Retry. All-runs history table at bottom.

#### `SandboxLive.Index` (`/sandboxes`)

LiveView stream of sandbox cards. Subscribes to `"sandboxes:updates"`. Events: `"stop_sandbox"`, `"destroy_sandbox"`. Status visual indicators (animated spinner for building, color-coded badges).

#### `SandboxLive.Show` (`/sandboxes/:id`)

Container detail with real-time log streaming. Subscribes to `"sandbox:<id>"`. Handles `{:log_line, line}` and `{:status_change, new_status}`.

Log viewer uses `phx-update="stream"` + `phx-hook="AutoScroll"` (auto-scrolls if within 100px of bottom). Events: `"stop_container"`, `"restart_container"`, `"destroy_container"`. Shows eval goals with difficulty badges, optional error details.

### 7.3 Controllers

**`API.ToolController`** (`POST /api/tools/search`) — container web-search proxy. Accepts `%{"query" => query}`, calls `WebSearch.execute/1`, returns `{status: "ok", results: [...]}` or `{status: "error", error: "..."}`.

**`PageController`** — vestigial scaffolding; defines `home/2` but no route maps to it.

**`ErrorHTML` / `ErrorJSON`** — standard Phoenix error renderers.

### 7.4 Layouts & Components

#### Root Layout (`root.html.heex`)

Sets `data-theme="dark"` on `<html>`. Includes inline script to enforce dark theme on every load. Loads `app.css` and `app.js` as phx-tracked static assets. Renders `@inner_content`.

#### App Layout (`Layouts.app/1`)

Structure: sticky glass-morphism header → centered `max-w-5xl` main → footer. Header contains SkillToSandbox logo + nav links (Dashboard, Skills, Sandboxes). Footer shows version and stack. Flash group floats outside main.

#### Core Components (`CoreComponents`)

Imported everywhere via `html_helpers()`:

| Component | Purpose |
|---|---|
| `<.flash>` | DaisyUI toast (info/error), top-right, JS-dismissible |
| `<.button>` | Renders `<button>` or `<.link>` with `btn btn-primary` styling |
| `<.input>` | All HTML input types + select/textarea/checkbox; auto-derives id/name/value from `field` |
| `<.header>` | `<h1>` with optional subtitle and actions slot |
| `<.table>` | DaisyUI zebra table; supports LiveView streams |
| `<.list>` | DaisyUI list component |
| `<.icon>` | `<span class="hero-<name>">` (Heroicons via CSS) |

---

## 8. Configuration

### Environment Variables

| Variable | Default | Purpose |
|---|---|---|
| `LLM_PROVIDER` | `"openai"` | LLM provider: `"openai"` or `"anthropic"` |
| `LLM_API_KEY` | *required* | API key for the LLM provider |
| `LLM_MODEL` | `"gpt-4o"` / `"claude-sonnet-4-20250514"` | Model to use |
| `SEARCH_API_PROVIDER` | `"tavily"` | Web search provider |
| `SEARCH_API_KEY` | — | Tavily API key |
| `CLI_TIMEOUT_MS` | `"30000"` | CLI tool timeout in milliseconds |
| `GITHUB_TOKEN` | — | Optional GitHub API token for higher rate limits |
| `PORT` | `4000` | HTTP port |
| `PHX_SERVER` | — | Set to enable server mode in releases |
| `DATABASE_PATH` | *required (prod)* | Path to SQLite DB file |
| `POOL_SIZE` | `5` (prod) | DB connection pool size |
| `SECRET_KEY_BASE` | *required (prod)* | Phoenix session signing key |
| `PHX_HOST` | `"example.com"` (prod) | Hostname for URL generation |
| `DNS_CLUSTER_QUERY` | — | Optional DNS query for clustering |

In dev/test: a `.env` file is auto-loaded by `runtime.exs` (real env vars always take precedence).

### Notable Config Flags

- `validate_packages: true` — enables live npm/PyPI registry validation (configurable in `config.exs`)
- `validate_packages_timeout_ms: 5_000` — timeout for package validation
- `debug_heex_annotations: true`, `debug_attributes: true`, `enable_expensive_runtime_checks: true` — dev-only LiveView debug flags

---

## 9. Frontend & Assets

### CSS (`assets/css/app.css`)

```css
@import "tailwindcss" source(none);
@source "../css";
@source "../js";
@source "../../lib/skill_to_sandbox_web";
@plugin "../vendor/heroicons";
@plugin "../vendor/daisyui" { themes: false }
@plugin "../vendor/daisyui-theme" { /* dark + light themes */ }
```

**Two custom DaisyUI themes:**

| Theme | Description |
|---|---|
| `dark` (default) | Deep navy-purple bg (`oklch(14% 0.015 270)`), rose-pink primary, electric cyan accent |
| `light` | High-key light base, same color palette at lighter values |

**Custom utilities:** `.bg-mesh` (radial gradient), `.glass-panel` (frosted glass + blur), `.glass-panel-hover` (translateY lift), `.glow-primary`, `.glow-accent`, `.stat-value`, `.back-btn`.

### JavaScript (`assets/js/app.js`)

- Phoenix LiveSocket with `longPollFallbackMs: 2500`
- Colocated hooks auto-bundled via `phoenix-colocated/skill_to_sandbox`
- **`AutoScroll` hook** — auto-scrolls log viewer to bottom; only scrolls if within 100px of bottom (threshold-based follow)
- Topbar progress bar on `phx:page-loading-start` / `stop`
- Dev-only: server log streaming + click-to-editor navigation

### Build Tooling

| Tool | Version | Purpose |
|---|---|---|
| esbuild | 0.25.4 | `js/app.js` → `priv/static/assets/js/app.js`, ES2022 |
| Tailwind CLI | 4.1.12 | `assets/css/app.css` → `priv/static/assets/css/app.css` |

---

## 10. OTP Supervision Tree

```
SkillToSandbox.Supervisor (one_for_one)
├── SkillToSandboxWeb.Telemetry          # Metrics supervisor
├── SkillToSandbox.Repo                  # Ecto SQLite repo
├── Ecto.Migrator                        # Auto-run migrations at startup
├── DNSCluster                           # Optional distributed clustering
├── Phoenix.PubSub (SkillToSandbox.PubSub)
├── Registry (PipelineRegistry, :unique) # run_id → Runner PID
├── Task.Supervisor (TaskSupervisor)     # Async LLM + Docker tasks
├── Pipeline.Supervisor (DynamicSup)     # Runner GenServer parent
├── Registry (SandboxRegistry, :unique) # sandbox_id → Monitor PID
├── DynamicSupervisor (SandboxMonitorSupervisor) # Monitor parent
├── Task → Recovery.recover_on_startup/0 # 1s delay, then resume interrupted runs
└── SkillToSandboxWeb.Endpoint           # HTTP server (Bandit)
```

### PubSub Topics

| Topic | Subscribers | Messages |
|---|---|---|
| `"pipeline:<run_id>"` | `PipelineLive.Show` | `{:pipeline_update, payload}` |
| `"sandbox:<id>"` | `SandboxLive.Show` | `{:log_line, line}`, `{:status_change, status}` |
| `"sandboxes:updates"` | `SandboxLive.Index` | `{:sandbox_status_change, sandbox_id, status}` |

---

## 11. External Integrations

| Service | Module | Protocol | Auth |
|---|---|---|---|
| Anthropic Claude | `LLMClient` | `Req.post` → `https://api.anthropic.com/v1/messages` | `x-api-key` header |
| OpenAI GPT | `LLMClient` | `Req.post` → `https://api.openai.com/v1/chat/completions` | `Authorization: Bearer` |
| Tavily Search | `WebSearch` | `Req.post` → `https://api.tavily.com/search` | `api_key` in request body |
| GitHub API | `GitHubFetcher` | `Req.get` → GitHub REST API | Optional `Authorization: token` |
| GitHub raw content | `GitHubFetcher` | `Req.get` → `raw.githubusercontent.com` | Optional `Authorization: token` |
| npm Registry | `PackageValidator` | `Req.get` → `https://registry.npmjs.org/<pkg>/latest` | None |
| PyPI | `PackageValidator` | `Req.get` → `https://pypi.org/pypi/<pkg>/json` | None |
| Docker daemon | `Docker` | `System.cmd("docker", ...)` | Local Docker socket |

All HTTP uses `Req` exclusively. No `:httpoison`, `:tesla`, or `:httpc`.

---

## 12. Test Suite

**Database:** SQLite test database (`skill_to_sandbox_test.db`)  
**LLM calls in tests:** Use `"test"` provider stub — no real API calls  
**Docker integration tests:** Tagged `@moduletag :docker`, excluded by default (run with `mix test --include docker`)

### Test Files

| File | What is tested |
|---|---|
| `skills/parser_test.exs` | YAML frontmatter, keyword detection, `parse_directory/1`, `extract_allowed_tools_deps/1`, real fixture |
| `skills/git_hub_fetcher_test.exs` | URL parsing (blob/tree/raw), file fetch, directory fetch (mocked HTTP via Bypass) |
| `skills/dependency_scanner_test.exs` | `package.json`, `requirements.txt`, `pyproject.toml` parsing, `-r` includes, multi-file merging |
| `skills/package_validator_test.exs` | npm/PyPI validation (mocked HTTP via Bypass) |
| `skills/canonical_deps_test.exs` | Human name → canonical package name mapping |
| `analysis/analyzer_test.exs` | `extract_json/1`, `validate_spec/1`, `ensure_react_dom/1`, `merge_scanner_deps/2`, prompt construction, DB roundtrip |
| `analysis/code_dependency_extractor_test.exs` | CDN URL extraction, JS/TS/Python import extraction |
| `analysis/dependency_relevant_files_test.exs` | File selection, priority ordering, budget truncation |
| `pipeline/runner_test.exs` | GenServer lifecycle, all state transitions, PubSub broadcasts, DB persistence, `step_timings`, approve/retry/re_analyze state guards, resume mode, Recovery behavior |
| `sandbox/build_context_test.exs` | Context dir assembly, file layout, tool scripts, directory skills vs single-file skills |
| `sandbox/dockerfile_builder_test.exs` | Dockerfile generation (npm/pip/yarn/pnpm), system packages, env vars, entrypoint |
| `integration/dependency_detection_test.exs` | End-to-end scanner + parser + merge |
| `integration/dependency_pipeline_test.exs` | Scanner + parser + analyzer merge (npm/pip/pyproject/allowed-tools) |
| `integration/pipeline_integration_test.exs` | Full pipeline with real Docker build (`@moduletag :docker`) |
| `agent/runner_test.exs` | `strip_command/1` — fence stripping, `$` prefix stripping, signal passthrough |
| `agent/prompt_builder_test.exs` | `build/1` — npx preference, bare tools, empty/missing frontmatter |
| `controllers/` | API controller (error HTML/JSON, tool search) |

**Test design notes:**
- Runner tests use `Ecto.Adapters.SQL.Sandbox.mode(Repo, {:shared, self()})` to share the DB connection across GenServer and Task processes within the same test
- `test/fixtures/frontend_design_skill.md` is a real-world skill used by parser tests
- `lazy_html` is used for HTML structure assertions (over raw HTML string matching)

---

## 13. Development Workflow

### Mix Aliases

| Alias | Steps |
|---|---|
| `mix setup` | `deps.get`, `ecto.setup`, `assets.setup`, `assets.build` |
| `mix ecto.setup` | `ecto.create`, `ecto.migrate`, `run priv/repo/seeds.exs` |
| `mix ecto.reset` | `ecto.drop`, `ecto.setup` |
| `mix test` | `ecto.create --quiet`, `ecto.migrate --quiet`, `test` |
| `mix assets.setup` | `tailwind.install --if-missing`, `esbuild.install --if-missing` |
| `mix assets.build` | `compile`, `tailwind skill_to_sandbox`, `esbuild skill_to_sandbox` |
| `mix assets.deploy` | Minified tailwind + esbuild + `phx.digest` |
| `mix precommit` | `compile --warnings-as-errors`, `deps.unlock --unused`, `format`, `test` (runs in `:test` env) |

### First-time setup

```bash
mix setup          # install deps, create DB, run migrations, seed data
mix phx.server     # start server at http://localhost:4000
# or:
iex -S mix phx.server
```

Requires: Elixir ~1.15, Docker installed and running, `LLM_API_KEY` set in `.env` (or environment).

### Pre-commit

```bash
mix precommit      # runs in :test env: compile (strict), clean unused deps, format, full test suite
```

### Running Tests

```bash
mix test                         # all unit/integration tests (no Docker)
mix test --include docker        # also runs Docker integration tests
mix test test/specific_test.exs  # single file
mix test --failed                # re-run previously failed tests
```

### Seeds

`priv/seeds.exs` is idempotent — only inserts if no skills exist. Seeds one sample skill:

- **Name:** `frontend-design`
- **Description:** "Create distinctive, production-grade frontend interfaces with innovative layouts, creative use of CSS and JavaScript, and thoughtful UX design."
- **Content:** A multi-section SKILL.md covering design thinking, modern CSS techniques, React/Vue/Svelte/Next.js, Motion library for animation, responsive design, tools, and anti-patterns.
- `parsed_data` is populated at seed time by running `Parser.parse/1`.

### Mix Backfill Task

`mix skill_to_sandbox.backfill_file_tree` — for existing single-file skills created before the directory support migration (`20260224000001`), sets `file_tree` to `%{"SKILL.md" => raw_content}` for consistency.

---

## 14. Current Status & Known Gaps

### What is fully implemented and working

- Complete pipeline from skill ingestion → LLM analysis → user review → Docker build → container monitoring
- Both Anthropic and OpenAI LLM providers
- Single-file skill (`"file"`) and directory skill (`"directory"`) ingestion paths
- GitHub URL fetching (blob and tree URLs)
- ZIP file upload with path-traversal-safe extraction
- LLM package validation against npm/PyPI registries
- Dependency scanning from `package.json`, `requirements.txt`, `pyproject.toml`
- Code dependency extraction from JS/TS imports and CDN URLs
- Real-time pipeline progress via PubSub/LiveView
- Real-time container log streaming via PubSub/LiveView
- Container health polling every 5s
- Pipeline crash recovery on application restart
- CLI and web search tools (proxied through host for security)
- Full test suite including end-to-end Docker integration tests
- Agent loop module (`Runner`) with DONE/STUCK signals, step logging, pre-flight check, and defense-in-depth command stripping
- Skill-aware prompt builder (`PromptBuilder`) that extracts `allowed-tools` invocation style from skill frontmatter

### Known gaps and incomplete features

1. **Port mappings not used:** `sandboxes.port_mappings` field and `Docker.run_container/3` `:ports` option both exist, but `execute_docker_build/2` in the Runner does not pass any ports when starting containers. Port mapping infrastructure exists but is inactive.

2. **Only one web search provider:** `WebSearch.do_search/4` has a catch-all clause returning an error for unsupported providers. Only `"tavily"` is implemented.

3. **Vestigial PageController:** `PageController.home/2` is defined but no route maps to it (`/` is handled by `DashboardLive`). The controller is scaffolding residue.

4. **Dark-mode only:** The root layout hard-forces `data-theme="dark"` via an inline script. The `Layouts.theme_toggle/1` component exists but has no practical effect while the hard-lock is in place.

5. **Directory fetch SKILL.md not enforced:** `GitHubFetcher` silently continues if no `SKILL.md` is found in a directory fetch (documented decision in a code comment at line 192–195 of `git_hub_fetcher.ex`). The parser attempts to find another `.md` at root.

6. **No CI/CD:** No `.github/workflows/`, no Makefile, no Dockerfile at the project root. The project must be set up and run manually.

7. **No authentication:** All routes are publicly accessible. Designed for internal research use.

8. **SQLite WAL artifacts:** `skill_to_sandbox_dev.db`, `skill_to_sandbox_dev.db-shm`, and `skill_to_sandbox_dev.db-wal` are runtime artifacts at the project root. The test database `skill_to_sandbox_test.db` is also there.

9. **README not project-specific:** `README.md` contains only boilerplate Phoenix quickstart content. This document (`PROJECT_CONTEXT.md`) serves as the actual project documentation.

10. **`erl_crash.dump` present:** An Erlang crash dump file exists at the project root, indicating a past crash. This is a runtime artifact and can be deleted safely.

11. **~~Browser-automation skills (Playwright/Chromium) fail due to missing OS libraries in slim images~~** — ✅ Fixed (2026-03-10). The root cause was two-fold: (a) `DockerfileBuilder` was not running `apt-get update` before `apt-get install`, so the slim image package index was empty; (b) the LLM was not prompted to include the 20 required Chromium OS shared libraries in `system_packages` for browser-automation skills.

    **Fixes applied:**
    - `dockerfile_builder.ex`: Changed the apt-get `RUN` instruction to `apt-get update && apt-get install -y --no-install-recommends ... && rm -rf /var/lib/apt/lists/*` — the package index is now always refreshed before any install.
    - `analyzer.ex`: Added `ensure_browser_system_deps/1` — deterministically injects all 20 Chromium OS packages into `system_packages` and `npx playwright install chromium` into `post_install_commands` whenever browser-related npm packages (`playwright`, `puppeteer`, `agent-browser`, etc.) are detected. No LLM judgment required.
    - `analyzer.ex` `@system_prompt`: Updated with explicit instructions listing the 20 required packages and `node:20` base image for browser skills.
    - `skills/parser.ex`: Added detection patterns for `Puppeteer`, `Selenium`, and `WebDriver` keywords.
    - `skills/canonical_deps.ex`: Added canonical npm mappings for `puppeteer`, `selenium-webdriver`, `@seleniumhq/selenium`, and `@playwright/test`.

    **Verified (2026-03-10, sandbox `c92b8ca`):** Full end-to-end browser test completed successfully — `npx agent-browser screenshot` saved `/workspace/page.png` after navigating to `example.com`. Chromium launched without any missing-library errors. See Section 15 for the detailed experiment log.

12. **`PromptBuilder` extracts `npx` itself as a bare tool (minor noise):** The `parse_invocations/1` regex in `SkillToSandbox.Agent.PromptBuilder` extracts bare-tool candidates from `Bash(...)` patterns. For input like `Bash(npx agent-browser:*)`, the npx regex correctly captures `agent-browser → npx agent-browser`. However, the bare-tool fallback regex also captures `npx` as a standalone package name (since `npx` is a valid `[a-zA-Z0-9@/\-]+` token at the start of the match), and `npx` is not in the npx map (only `agent-browser` is), so it survives the reject filter. Result: the prompt includes both `- agent-browser → invoke as: npx agent-browser <subcommand>` and `- npx → invoke as: npx <subcommand>`. The latter line is harmless but misleading — `npx` itself is not a skill tool. **Fix:** Add a blocklist of reserved/meta tokens to `parse_invocations/1`: `@non_tool_tokens ~w(npx node npm yarn pnpm python pip)` — reject any candidate whose package name is in this list.

13. **`npx agent-browser navigate --screenshot <path>` does not save the screenshot file:** The `navigate` subcommand of `agent-browser` accepts a `--screenshot` flag, but in the version tested, the flag only controls display behavior (or is silently ignored) and does **not** write the file to the specified path. The correct way to capture a screenshot is via the dedicated `screenshot` subcommand: `npx agent-browser screenshot <path>`. This is a behavioral quirk of the `agent-browser` CLI and not a system error. The LLM self-corrected in the 2026-03-10 test (step 2 detected the missing file, step 3 used the correct subcommand), but one step was wasted. **Fix (optional):** Add a note to the `PromptBuilder` base instructions or to the `agent-browser`-specific instructions clarifying the correct subcommand for screenshots. Alternatively, document this in the `agent-browser` eval goals generated by the LLM.

14. **Agent system not integrated into the web UI or pipeline flow:** `Agent.Runner` and `Agent.PromptBuilder` exist as standalone modules and can be invoked from IEx, but there is no LiveView or pipeline step that exposes agent evaluation to end users. The sandbox detail page (`SandboxLive.Show`) shows logs and container controls but has no "Run Agent Task" form. **Next step:** Add an agent task form to `SandboxLive.Show` — a text input for the task description, a "Run" button that calls `Agent.Runner.run/3` asynchronously, and a results panel showing step-by-step output via PubSub.

### Migration history summary

| Date | Migration | Change |
|---|---|---|
| 2026-02-11 | `create_skills` | Initial `skills` table |
| 2026-02-11 | `create_sandbox_specs` | Initial `sandbox_specs` table |
| 2026-02-11 | `create_sandboxes` | Initial `sandboxes` table |
| 2026-02-11 | `create_pipeline_runs` | Initial `pipeline_runs` table |
| 2026-02-24 | `add_skill_directory_support` | Added `source_type`, `source_root_url`, `file_tree` to `skills` |
| 2026-02-24 | `add_sandbox_spec_skill_support` | Added `skill_mount_path`, `post_install_commands` to `sandbox_specs` |

The 2026-02-24 migrations added directory skill support, indicating this was a post-initial-release feature addition. The `mix skill_to_sandbox.backfill_file_tree` task exists to migrate existing single-file skill records to the new schema.

---

## 15. Live Experiment Notes

### 2026-03-10 — Manual sandbox interaction and agentic loop test

**Skill tested:** `agent-browser` (GitHub directory skill — browser automation CLI for AI agents)  
**Sandbox container:** `d1e2b784832801cea3ae06813da5c889e6bb25b234bcc0816670d439c19aabef`  
**Base image:** `node:20-slim` | **Node version:** `v20.20.1`

#### What was verified working

| Test | Result |
|------|--------|
| `Docker.container_status/1` | ✅ `{:ok, "running"}` |
| `tool_manifest.json` readable from container | ✅ Valid JSON with `cli_execution` + `web_search` |
| `SKILL.md` and full directory tree in `/workspace/skill/` | ✅ (`SKILL.md`, `_repo_root/`, `references/`, `templates/`) |
| `node_modules/` present in `/workspace/` | ✅ npm install ran during build |
| `/tools/cli_execution.sh` + `/tools/web_search.sh` present and executable | ✅ |
| `CLI.execute/1` shell execution path | ✅ `{:ok, "hello from sandbox"}` |
| `working_dir` override in `CLI.execute/1` | ✅ `{:ok, "/workspace/skill"}` |
| Web search proxy network path (container → host) | ✅ Request reached host; 401 due to missing `SEARCH_API_KEY` only |
| UI log streaming via `tee /proc/1/fd/1` | ✅ All exec output appeared live in `/sandboxes/:id` log viewer |

#### Agentic loop experiment

Ran a 5-step `Enum.reduce_while` loop using `LLMClient.chat/2` (real LLM calls) where each step:
1. Asked the LLM for the next bash command given the task + previous output
2. Executed the command in the container via `CLI.execute/1`
3. Fed the output back as context for the next step

**Task:** "Open https://example.com, take a screenshot named page.png, then confirm the file exists"

**Outcome:**
- Steps 1–4: LLM attempted `agent-browser --url ... --screenshot ...` → `command not found` (correct tool name, wrong invocation — should be `npx agent-browser open ...`)
- Step 5: LLM **self-corrected** without being told — issued `npm install -g agent-browser` to install the missing global binary. Succeeded (262 packages installed).
- Loop exhausted at 5 steps before attempting the screenshot after installation.

**Key finding:** The agentic loop architecture works correctly end-to-end. The LLM reasons about failures and adapts. Increasing `max_steps` would likely yield a successful screenshot attempt — blocked only by the Playwright OS library issue (see Known Gap #11).

#### The step limit question

The 5-step cap was set arbitrarily in the ad-hoc IEx experiment. The experiment consumed all 5 steps just recovering from environment setup problems (wrong invocation style, missing global binary) — leaving zero steps for the actual task work. This is a known failure mode for agentic loops: **environmental bootstrapping can silently eat your entire step budget before any real work begins.**

**Recommended limit for a proper agent runner: 10–15 steps**, with the following reasoning:

- Simple tasks (write a file, run a script, check output) typically need 2–4 steps
- Tasks with environment recovery (wrong command, missing tool, install needed) need 4–8 steps
- Tasks with multi-stage browser workflows (open, wait, snapshot, interact, verify) need 5–10 steps
- A hard cap is still important — without one, a stuck agent in a bad failure loop (e.g. same wrong command on every step) will run indefinitely and burn API credits

**The better approach is not just a higher number, but a smarter termination strategy:**
1. A hard cap (e.g. 15 steps) as a safety ceiling
2. A `DONE` signal the LLM can return when it considers the task complete (already implemented in the experiment)
3. A `STUCK` or `FAILED` signal the LLM can return when it determines the task is impossible (not yet implemented)
4. Deduct "wasted" steps from setup failures from a separate budget — or prime the environment before the loop starts (e.g. verify `npx agent-browser --version` succeeds before starting the task loop)

**Short answer: yes, increase to at least 12 for the next experiment**, but more importantly, fix the environment issues first (Playwright libs, correct `npx` invocation in the system prompt) so steps aren't burned on recovery before the agent even starts.

#### Lessons for improving the system

1. **Strip markdown fences from LLM output** before executing as bash — the LLM frequently wraps commands in ` ```bash ... ``` ` fences despite being told not to. Use a regex like `~r/```(?:bash)?\n?(.*?)```/s` to extract the raw command.
2. **Use `npx agent-browser` not `agent-browser`** — the skill's `allowed-tools` frontmatter says `Bash(npx agent-browser:*)` which is the correct form. The LLM system prompt should mirror this.
3. **Playwright requires OS libs in slim images** — see Known Gap #11 for the full fix.
4. **`/proc/1/fd/1` tee trick enables live UI log streaming** — any command piped through `tee /proc/1/fd/1` appears in the sandbox log viewer in real time.
5. **5 steps is too few** — increase to 12–15 for real tasks, and add a `STUCK` termination signal alongside `DONE` so the LLM can self-terminate on impossible tasks rather than spinning out the full budget.

### 2026-03-10 — Agent loop validation test (sandbox c92b8ca)

**Purpose:** Validate the end-to-end agent loop architecture (LLM → strip_fences → CLI.execute → context accumulation → next LLM call) against a live sandbox container.

#### What was verified working

| Test | Result |
|------|--------|
| Container alive | ✅ `{:ok, "alive\nv20.20.1"}` |
| `tool_manifest.json` present in `/workspace/` | ✅ |
| CLI execution (`node -v`, `ls`) | ✅ |
| Log streaming via `tee /proc/1/fd/1` to UI sandbox logs | ✅ All exec output appeared live in `/sandboxes/:id` log viewer |
| `DONE` termination signal | ✅ Fired correctly on step 6 |
| LLM self-correction | ✅ Dropped `$` prefix on step 5 after 2 failures |
| End-to-end agent loop architecture | ✅ LLM → strip_fences → CLI.execute → context → LLM |

#### Issues found

**Issue 1 (Bug in ad-hoc loop code — prompt context format teaches LLM to use `$` prefix):**

- **Root cause:** The context accumulation line `"\n\n$ #{command}\n#{output}\n\nNext command (or DONE/STUCK):"` prepends `$` to each command in the history. The LLM sees this pattern in its context window and mimics it by including `$` in its next output.
- **Effect:** Bash receives `$ head -n 5 /workspace/tool_manifest.json` and tries to execute `$` as a command, failing with `/bin/bash: line 1: $: command not found`.
- **Wasted steps:** 2 steps (steps 3–4) burned on the same bad command before self-correction.
- **Fix:** Remove the `$` prefix from context accumulation. Change `"\n\n$ #{command}\n..."` to `"\n\nCommand: #{command}\n..."` or plain `"\n\n#{command}\n..."`. Also add `$` prefix stripping to `strip_fences` as defense-in-depth.

**Issue 2 (No self-correction prompt feedback):**

- The error message from bash (`/bin/bash: line 1: $: command not found`) was passed back to the LLM as context, but the LLM retried the exact same wrong command twice (steps 3–4) instead of correcting on the first retry.
- The system prompt does not explicitly instruct the LLM: "if your previous command failed, examine the error and try a different approach."
- Adding this instruction would reduce wasted steps on recoverable errors by prompting the LLM to reason about the failure before retrying.

#### Step budget observation

- The task (`node -v` + `ls` + `head`) required 5 execution steps (steps 1–5) + 1 terminal `DONE` step = 6 total.
- 2 of those 5 execution steps were wasted on the `$` prefix bug.
- Without the bug, this task would have completed in 4 steps total (3 execution + 1 `DONE`).
- Confirms: small bugs in the loop code disproportionately waste the step budget. A 2-step waste on a 4-step task is a 50% overhead — significant at scale.

#### Fix required in agent runner (when built)

The proper agent runner module (`lib/skill_to_sandbox/agent/runner.ex` — not yet built, see Section 16) must:

1. **NOT** use `$` as a command prefix in context history — use `"Command: #{command}"` or plain `"#{command}"` instead.
2. Add `$` prefix stripping alongside fence stripping as defense-in-depth: `String.trim_leading(command, "$ ")`.
3. Include a self-correction instruction in the system prompt: "If a command failed, analyze the error output and try a different approach — do not retry the exact same command."

### 2026-03-10 — First successful end-to-end browser automation run (sandbox c92b8ca)

**Purpose:** Validate the completed `Agent.Runner` and `Agent.PromptBuilder` modules with a real browser automation task, using the browser-dependency fixes from the same session.  
**Invocation:** `Runner.run(task, container_id, system_prompt: PromptBuilder.build(skill.parsed_data))`  
**Task:** "Navigate to https://example.com and take a screenshot named page.png, then confirm the file exists"  
**Skill:** `agent-browser` (ID 5) — browser automation CLI skill  
**Container:** `c92b8ca08bb24162a1f7b62007b885c70df885013f310cd62a8e4b39a9b70992`

#### Step-by-step execution

| Step | Command | Output | Result |
|------|---------|--------|--------|
| 1 | `npx agent-browser navigate https://example.com --screenshot /workspace/page.png` | `✓ Example Domain` / `https://example.com/` | ✅ Navigated; screenshot flag silently ignored |
| 2 | `ls /workspace/page.png` | `ls: cannot access '/workspace/page.png': No such file or directory` | ⚠️ File not saved (LLM self-corrected) |
| 3 | `npx agent-browser screenshot /workspace/page.png` | `✓ Screenshot saved to /workspace/page.png` | ✅ File written |
| 4 | `ls /workspace/page.png` | `/workspace/page.png` | ✅ Confirmed |
| — | `DONE` | — | ✅ Task complete |

**Total steps: 4 execution steps + `DONE` = 5 turns. Well within the 12-step budget.**

#### What worked

| Component | Result |
|---|---|
| `PromptBuilder.build/1` injected `npx agent-browser` invocation | ✅ LLM used `npx agent-browser` on first try — no `command not found` errors |
| `ensure_browser_system_deps/1` injected 20 Chromium OS packages | ✅ Chromium launched without any missing-library errors |
| `dockerfile_builder.ex` `apt-get update` fix | ✅ All OS packages installed cleanly during image build |
| `Runner.strip_command/1` | ✅ No `$` prefix issues — LLM output was clean throughout |
| Self-correction system prompt | ✅ LLM detected missing file on step 2 and pivoted to the correct `screenshot` subcommand |
| `DONE` signal | ✅ Fired correctly after the confirmation `ls` |
| Live log streaming via `tee /proc/1/fd/1` | ✅ All step output appeared in the `/sandboxes/:id` log viewer in real time |

#### What didn't work perfectly

- **`navigate --screenshot <path>` does not save the file.** The `--screenshot` flag on the `navigate` subcommand was silently ignored — the file was not written. This is a behavioral quirk of the `agent-browser` CLI (the dedicated `screenshot` subcommand is the correct approach). One step was wasted on the detection `ls`. See Known Gap #13.
- **`PromptBuilder` added a spurious `npx` tool line.** The prompt included `- npx → invoke as: npx <subcommand>` in addition to the correct `- agent-browser → invoke as: npx agent-browser <subcommand>`. Harmless but noisy. See Known Gap #12.

#### Significance

This is the **first confirmed end-to-end browser automation run** in the project: `PromptBuilder` → `Runner` → `npx agent-browser` → real Chromium browser → screenshot captured → file confirmed → `DONE`. All five major infrastructure pieces (dependency injection, Dockerfile, command stripping, prompt building, self-correction) functioned correctly together.

---

## 16. Recommended Fixes for Next Agent

> This section is written as a prioritized, actionable brief for a future agent tasked with addressing the issues discovered during live experimentation. Read Section 15 first for the full experimental context.

### Priority order

Fix these in sequence. Each one is a prerequisite for properly validating the next.

---

### Fix 1 (Critical): Playwright OS system libraries missing from browser-skill sandbox images

> **Status: ✅ Addressed** — `ensure_browser_system_deps/1` in `analyzer.ex` deterministically injects all 20 Chromium OS packages; `dockerfile_builder.ex` now runs `apt-get update` before every install; parser and canonical deps updated for Puppeteer/Selenium/WebDriver. Verified end-to-end in sandbox `c92b8ca` on 2026-03-10.

**Where the problem is:** `SkillToSandbox.Analysis.Analyzer` — specifically the LLM system prompt in `@system_prompt` at the top of `lib/skill_to_sandbox/analysis/analyzer.ex`, and `SkillToSandbox.Sandbox.DockerfileBuilder` in `lib/skill_to_sandbox/sandbox/dockerfile_builder.ex`.

**What happens:** When a skill uses browser automation (Playwright, Puppeteer, `agent-browser`, any Chromium-based tool), the LLM correctly adds `post_install_commands: ["npx playwright install chromium"]` to the spec. However, it fails to add the required OS-level shared libraries to `system_packages`. Slim Debian-based images (`node:20-slim`, `python:3.x-slim`) do not ship these libraries. The result is that `npx playwright install chromium` downloads the Chromium binary successfully but Chromium cannot launch at runtime because it cannot find `libglib2.0-0`, `libnss3`, and 17 other shared libraries.

Additionally, even if an agent tries to install them post-hoc via `apt-get install`, it will fail with `E: Unable to locate package` because `apt-get update` was never run in the image — the package index is empty in slim images.

**The exact list of missing packages** (confirmed by Playwright's own diagnostic output):
```
libglib2.0-0 libnspr4 libnss3 libatk1.0-0 libatk-bridge2.0-0 libdbus-1-3
libcups2 libxcb1 libxkbcommon0 libatspi2.0-0 libx11-6 libxcomposite1
libxdamage1 libxext6 libxfixes3 libxrandr2 libgbm1 libcairo2
libpango-1.0-0 libasound2
```

**Two valid approaches to fix this — choose one:**

**Option A (Preferred): Update the LLM system prompt to instruct the LLM to include these packages**

In `analyzer.ex`, add a specific instruction to the `@system_prompt` constant that tells the LLM: when the skill mentions browser automation, Playwright, Puppeteer, Chromium, or `agent-browser`, it must include all Playwright system dependencies in `system_packages` AND must ensure `apt-get update` runs before any `apt-get install`. The `DockerfileBuilder` already runs `apt-get install` from `system_packages` in a single `RUN` layer — it should be updated to prepend `apt-get update -y &&` before the install command so the package index is always fresh.

The specific change to `dockerfile_builder.ex`: find the line that generates the apt-get RUN instruction and change it from:
```
RUN apt-get install -y #{packages}
```
to:
```
RUN apt-get update -y && apt-get install -y --no-install-recommends #{packages} && rm -rf /var/lib/apt/lists/*
```
The `--no-install-recommends` and `rm -rf /var/lib/apt/lists/*` are standard best practices to keep image size down.

**Option B (Nuclear, simpler): Switch base image for browser skills**

Use `mcr.microsoft.com/playwright:v1.x-noble` or `node:20` (full, not slim) as the base image for any skill that mentions browser automation. These images come with all dependencies pre-installed. The tradeoff is a much larger image (~1.5GB vs ~200MB for slim). The LLM prompt can be updated to choose this base image when it detects browser-related keywords in the skill.

**Verification:** After the fix, this command should succeed and print a version number without any warnings:
```elixir
CLI.execute(%{"command" => "npx playwright --version", "container_id" => cid})
```

---

### Fix 2 (High): LLM returns markdown-fenced commands instead of raw bash

> **Status: ✅ Addressed** — `Runner.strip_command/1` handles all common fence variants (` ```bash `, ` ```sh `, ` ```shell `, plain ` ``` `).

**Where the problem is:** The agent loop code (currently only exists as an ad-hoc IEx script — not yet a proper module). The LLM system prompt also contributes.

**What happens:** When instructed to respond with only a raw bash command, the LLM sometimes (often) wraps the command in markdown code fences:
```
```bash
echo "hello"
```
```
When this is passed directly to `CLI.execute/1`, bash receives ` ```bash ` as the first line and tries to execute it as a command, causing errors like `bash: ```bash: command not found`.

**The fix:** Add a response-cleaning step between `LLMClient.chat/2` and `CLI.execute/1`. Strip markdown fences from the LLM output before executing it. The following Elixir regex handles all common fence variants:

```elixir
defp strip_fences(text) do
  case Regex.run(~r/```(?:bash|sh|shell)?\n?(.*?)```/s, String.trim(text), capture: :all_but_first) do
    [command] -> String.trim(command)
    nil -> String.trim(text)
  end
end
```

This should be applied to every LLM response in the agent loop before execution. Additionally, update the system prompt to reinforce the constraint: add a concrete example of the desired output format and an explicit negative example showing what NOT to do (markdown fences).

**Verification:** Run `LLMClient.chat/2` with a task prompt and `IO.inspect` the raw response before and after stripping. Confirm that after stripping, the result is a single executable bash command with no backtick characters.

---

### Fix 3 (High): Agent system prompt does not reflect skill's `allowed-tools` invocation style

> **Status: ✅ Addressed** — `PromptBuilder.build/1` now extracts `allowed-tools` from `skill.parsed_data` and appends explicit invocation instructions to the system prompt.

**Where the problem is:** The system prompt built in the ad-hoc IEx experiment. If a proper agent runner module is built, this will live there.

**What happens:** The `agent-browser` skill's frontmatter specifies `allowed-tools: Bash(npx agent-browser:*)`. This means the correct invocation is `npx agent-browser <subcommand>`. However, the LLM — given only "agent-browser is installed" in the system prompt — infers it should call `agent-browser` as a bare command. Since `agent-browser` is a locally installed npm package (not globally linked), `agent-browser` is not on `PATH`. The LLM attempted this 4 times, failing each time, before resorting to `npm install -g agent-browser`.

**The fix has two parts:**

1. **System prompt:** Tell the agent explicitly how to invoke the skill's tools. The `allowed-tools` frontmatter is already parsed by `Skills.Parser` and stored in `skill.parsed_data["frontmatter"]["allowed-tools"]`. The agent loop should extract this and include it in the system prompt verbatim:
   ```
   This skill's allowed tools (exact invocation style):
   - Bash(npx agent-browser:*) → use: npx agent-browser <subcommand>
   ```

2. **Environment priming step (optional but recommended):** Before starting the agent loop, run a pre-flight check to verify the tool is callable. If `npx agent-browser --version` fails, either bail early with a clear error, or run a one-time setup command. This prevents the agent from burning 4+ steps discovering a solvable environment problem.

**Verification:** With the updated system prompt, step 1 of the agent loop should immediately attempt `npx agent-browser open https://example.com` instead of bare `agent-browser`.

---

### Fix 4 (Medium): Agent loop step budget and termination design

> **Status: ✅ Addressed** — `Runner.run/3` defaults to `max_steps: 12`, halts on `DONE`/`STUCK` signals, and returns `{:error, :step_limit, steps}` when the budget is exhausted.

**Where the problem is:** The agent loop has no home in the codebase yet — it was only written as an ad-hoc IEx script. When a proper agent runner is built (as a module, LiveView, or API endpoint), it needs a well-designed termination strategy.

**What happens with a fixed step cap:** The experiment used `Enum.reduce_while(1..5, ...)`. The 5-step cap was exhausted entirely on environmental recovery (wrong invocation style × 4, then install binary), leaving no budget for the actual task. This is the "environment bootstrap burn" failure mode — a structurally predictable problem for any agentic system where environment state is not guaranteed up-front.

**Recommended termination strategy for the agent runner:**

```elixir
# Pseudocode for a well-designed agent loop
def run_agent(task, container_id, opts \\ []) do
  max_steps = Keyword.get(opts, :max_steps, 12)
  
  Enum.reduce_while(1..max_steps, initial_context(task), fn step, context ->
    {:ok, response} = LLMClient.chat(system_prompt(), context)
    command = strip_fences(response)
    
    cond do
      command == "DONE" ->
        {:halt, {:ok, :completed}}
      
      command == "STUCK" ->
        {:halt, {:error, :agent_stuck}}
      
      true ->
        result = CLI.execute(%{"command" => command <> " 2>&1 | tee /proc/1/fd/1", "container_id" => container_id})
        {:cont, build_next_context(task, command, result, step)}
    end
  end)
  |> case do
    {:ok, :completed} -> {:ok, :done}
    {:error, :agent_stuck} -> {:error, "Agent reported task impossible"}
    context when is_binary(context) -> {:error, "Agent hit step limit (#{max_steps} steps)"}
  end
end
```

**Specific recommendations:**
- **`max_steps: 12`** as the default. This is enough for all realistic tasks (2–4 steps for simple scripting, 5–8 for browser workflows with retries) while preventing runaway loops.
- **Add `STUCK` as a valid response** alongside `DONE`. Instruct the LLM: "If you determine the task is impossible given the available tools and environment, respond with exactly: STUCK". This prevents the agent from exhausting the full budget on a definitively impossible task.
- **Do not use `DONE` as the default fallback** — the LLM should only return `DONE` when it has confirmed the task is complete (e.g. file exists, output matches expectation). The system prompt should make this explicit.
- **Log step count and timing** — when building the proper module, record `step_count` and `total_elapsed_ms` in the result. This data is valuable for calibrating the step budget over time.
- **Consider a separate "setup budget" vs "task budget"** — e.g. up to 3 steps allowed for environment verification/setup, then 10 steps for the actual task. If the setup budget is exhausted, return `{:error, :environment_not_ready}` rather than silently burning the task budget.

**Why not just set max_steps very high (e.g. 50)?** Two reasons: (1) cost — each step is an LLM API call, and a stuck agent at 50 steps burns ~50 LLM calls before stopping; (2) correctness signal — if a task requires more than 15 steps, it usually means either the task is too large and should be decomposed, or the agent is stuck in a loop. A lower cap forces better task scoping.

---

---

### Fix 5 (Medium): Agent loop context format causes LLM to add `$` prefix to commands

> **Status: ✅ Addressed** — `Runner.strip_command/1` strips `$` prefixes; context history uses `"Command: X"` format; system prompt includes self-correction instruction.

**Where the problem is:** The ad-hoc IEx loop code (no permanent module yet — will be in `lib/skill_to_sandbox/agent/runner.ex` when built).

**What happens:** The context accumulation line used in the experiment was:

```elixir
next = context <> "\n\n$ #{command}\n#{output}\n\nNext command (or DONE/STUCK):"
```

Every prior command appears in the LLM's context window prefixed with `$`, forming a pattern like:

```
$ node -v
v20.20.1

$ ls /workspace
node_modules
...

Next command (or DONE/STUCK):
```

The LLM reads this history and infers that the expected output format for commands includes the `$` prefix. It then produces `$ head -n 5 /workspace/tool_manifest.json` as its next response. When this string is passed to `CLI.execute/1`, bash receives `$` as the first token and attempts to execute it as a command name, resulting in `/bin/bash: line 1: $: command not found`. The LLM then retried the exact same prefixed command again (step 4) before finally dropping the `$` on step 5 after two failures.

**Observed in:** 2026-03-10 agent loop validation test (Section 15, second entry). Steps 3–4 wasted.

**The fix:**

1. **Change the context accumulation format** — replace `"$ #{command}"` with `"Command: #{command}"` or plain `"#{command}"` so the `$` prompt character never appears in the history:

   ```elixir
   # Before (causes LLM to echo $ prefix):
   next = context <> "\n\n$ #{command}\n#{output}\n\nNext command (or DONE/STUCK):"

   # After (neutral format, no prompt character to mimic):
   next = context <> "\n\nCommand: #{command}\n#{output}\n\nNext command (or DONE/STUCK):"
   ```

2. **Add `$` prefix stripping to `strip_fences` as defense-in-depth** — even with the context format fixed, the LLM may still occasionally echo `$` (e.g. if copying from an example in its training data). Extend the fence-stripping step to also strip a leading `$ `:

   ```elixir
   defp strip_fences(text) do
     cleaned =
       case Regex.run(~r/```(?:bash|sh|shell)?\n?(.*?)```/s, String.trim(text), capture: :all_but_first) do
         [command] -> String.trim(command)
         nil -> String.trim(text)
       end
     String.trim_leading(cleaned, "$ ")
   end
   ```

3. **Add a self-correction instruction to the system prompt** — instruct the LLM not to retry a failed command unchanged: "If the output of your previous command indicates an error, analyze the error and try a different approach. Do not repeat the exact same command that just failed."

**Why defense-in-depth matters here:** Fix 1 (context format) eliminates the primary cause. Fix 2 (`strip_fences` extension) catches residual `$` prefixes that might appear from other sources. Fix 3 (system prompt) reduces the number of wasted retries when a bad command does slip through. All three are low-cost and should be implemented together.

---

### Summary of recommended changes by file

| File | Change | Status |
|------|--------|--------|
| `lib/skill_to_sandbox/analysis/analyzer.ex` | Added `ensure_browser_system_deps/1` (injects 20 Chromium OS packages deterministically); updated `@system_prompt` with explicit browser skill instructions; added `@browser_npm_packages`, `@chromium_system_packages`, `@playwright_install_command` module attributes | ✅ Done |
| `lib/skill_to_sandbox/sandbox/dockerfile_builder.ex` | Changed apt-get RUN to `apt-get update && apt-get install -y --no-install-recommends ... && rm -rf /var/lib/apt/lists/*` | ✅ Done |
| `lib/skill_to_sandbox/skills/parser.ex` | Added `@dependency_patterns` entries for Puppeteer, Selenium, WebDriver | ✅ Done |
| `lib/skill_to_sandbox/skills/canonical_deps.ex` | Added canonical npm mappings for `puppeteer`, `selenium-webdriver`, `@seleniumhq/selenium`, `@playwright/test` | ✅ Done |
| `lib/skill_to_sandbox/agent/runner.ex` | Agent loop with fence+`$` stripping, `DONE`/`STUCK` signals, `max_steps: 12`, step logging, pre-flight check, `"Command: X"` context format, self-correction instruction | ✅ Done |
| `lib/skill_to_sandbox/agent/prompt_builder.ex` | Builds system prompts from skill `allowed-tools` frontmatter with correct npx invocation style | ✅ Done |
| `lib/skill_to_sandbox/agent/prompt_builder.ex` | Add `@non_tool_tokens` blocklist to prevent `npx`, `node`, `npm` etc. from appearing as fake tools | ⏳ Pending (Gap #12) |
| Web UI (`sandbox_live/show.ex`) | Add "Run Agent Task" form with task input, async `Runner.run/3` invocation, and step-by-step results panel | ⏳ Pending (Gap #14) |

All infrastructure fixes are complete and verified. Remaining work is UI integration and minor PromptBuilder cleanup.
