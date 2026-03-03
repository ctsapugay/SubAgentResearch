# Dependency Detection Implementation Plan

## Executive Summary

The SkillToSandbox pipeline occasionally misidentifies dependencies—adding false positives (e.g., Express.js when only the verb "express" appears) and using wrong versions (e.g., p5 ^1.4.0 instead of ^1.7.0 as specified in templates). This plan outlines a robust fix that improves correctness and completeness of dependency detection.

---

## 1. Context & Problem Statement

### 1.1 Current Pipeline Flow

1. **Skill ingestion** – User uploads a skill via paste, file upload, or GitHub URL.
2. **Parsing** – `Parser` extracts metadata, tools, frameworks, and dependencies from SKILL.md and .sh files using regex patterns.
3. **Dependency scanning** – `DependencyScanner` extracts packages from `package.json`, `requirements.txt`, and `pyproject.toml` when present.
4. **LLM analysis** – `Analyzer` builds a prompt from parsed data + file contents, sends to LLM, receives a JSON sandbox spec.
5. **Merge** – Manifest-based deps (from scanner) override/merge with LLM output.

### 1.2 Observed Failures (algorithmic-art skill)

| Issue | Example | Root Cause |
|-------|---------|------------|
| **False positive** | Express.js added when skill says "Express by creating p5.js generative art" | Parser regex `\bExpress\b` matches the verb; LLM treats "Express" in frameworks as Express.js |
| **Wrong version** | p5 ^1.4.0 instead of ^1.7.0 | p5.js version (1.7.0) is in `templates/viewer.html` which is never sent to the LLM |
| **Missing evidence** | LLM guesses from prose only | Code and HTML files (where imports and CDN URLs live) are not sent to the LLM |

### 1.3 Fundamental Gap

**Dependency evidence lives in:**

- **Manifests** – Already extracted by DependencyScanner ✓
- **Code files** – `require()`, `import`, `from` – **Not sent to LLM** ✗
- **HTML** – `<script src=".../p5.js/1.7.0/...">` – **Not sent to LLM** ✗
- **Prose** – Mentioned in SKILL.md – Sent, but unreliable (verb vs. package confusion) ⚠

The LLM receives only SKILL.md + up to 5 other `.md` files. `.html`, `.js`, `.py`, and other code files are never sent.

---

## 2. Current State: What Gets Sent to the LLM

| Section | Content | Source |
|---------|---------|--------|
| Name, Description | Skill metadata | Parsed frontmatter |
| Detected tools | Comma-separated | Parser regex on .md + .sh body |
| Detected frameworks | Comma-separated | Parser regex on .md + .sh body |
| Detected dependencies | Comma-separated | Parser regex on .md + .sh body |
| Scanned dependencies | package.json/requirements.txt/pyproject contents | DependencyScanner |
| Directory section | File list as text only | `file_tree` keys |
| Full skill content | SKILL.md (or primary .md) full text | `skill.raw_content` |
| Additional reference files | Up to 5 `.md` files, 4000 chars each | `additional_file_content/1` |

**Not sent:** `.html`, `.js`, `.ts`, `.tsx`, `.py`, `.json` (except as scanner output), `.sh` content, templates.

---

## 3. Solution Architecture

### 3.1 Layered Dependency Extraction

| Layer | Responsibility | Priority |
|-------|----------------|----------|
| **1. Manifest extraction** | Parse package.json, requirements.txt, pyproject.toml | Highest – these are authoritative |
| **2. Code/CDN extraction** | New module: extract imports and CDN URLs from file tree | High – deterministic evidence |
| **3. LLM inference** | Infer from full file contents when evidence is ambiguous | Medium – fills gaps |
| **4. Parser** | Provide hints from prose | Lowest – supporting only, not primary |

Merge rule: Manifest > Code/CDN extractor > LLM. Parser suggestions are advisory only.

### 3.2 Key Design Decisions

1. **Send dependency-relevant file contents to the LLM** – Include .html, .js, .ts, .py, etc., not just .md.
2. **Add deterministic extraction** – New module to extract imports and CDN URLs before/alongside LLM.
3. **Reframe parser output** – Present parser results as "mentioned in documentation" hints, not authoritative.
4. **Tighten parser patterns** – Reduce false positives (e.g., Express verb vs. Express.js).

---

## 4. Implementation Steps

### Phase 1: Expand File Content Sent to LLM

#### Step 1.1: Define dependency-relevant file types

**File:** `lib/skill_to_sandbox/analysis/dependency_relevant_files.ex` (new module)

**Tasks:**

1. Define a list of extensions that can contain dependency evidence:
   - Manifests: `.json` (for package.json), `requirements.txt`, `pyproject.toml`, `Cargo.toml`, `go.mod`, `Gemfile`
   - Code: `.js`, `.ts`, `.tsx`, `.jsx`, `.mjs`, `.cjs`, `.py`, `.rb`, `.go`, `.rs`
   - HTML: `.html`, `.htm`

2. Define manifest filenames (path-based, not just extension):
   - `package.json`, `package-lock.json`, `yarn.lock`, `pnpm-lock.yaml`
   - `requirements.txt`, `requirements*.txt`, `pyproject.toml`, `Pipfile`
   - `Cargo.toml`, `go.mod`, `Gemfile`, `Gemfile.lock`

3. Exclude patterns:
   - `node_modules/`, `vendor/`, `dist/`, `build/`
   - `LICENSE*`, `*.min.js` (optional – can include for CDN detection)
   - Binary extensions

**Deliverable:** Module with `dependency_relevant?(path)` and `manifest_file?(path)`.

---

#### Step 1.2: Implement file prioritization and budget

**File:** `lib/skill_to_sandbox/analysis/dependency_relevant_files.ex`

**Tasks:**

1. Assign priority scores:
   - Priority 1 (highest): Manifest files – full content always included
   - Priority 2: Files with likely import/CDN patterns (pre-scan for `require(`, `import `, `<script src=`)
   - Priority 3: Other code/HTML files

2. Implement `select_files_for_llm(file_tree, budget_in_chars)`:
   - Filter to dependency-relevant paths
   - Sort by priority
   - Take files until budget exhausted
   - For code files, optionally truncate to first N chars (imports often at top)

3. Suggested budget: 60,000–80,000 characters for "additional file content" to stay within context limits.

**Deliverable:** Function that returns `[{path, content}, ...]` for inclusion in the prompt.

---

#### Step 1.3: Replace `additional_file_content` in Analyzer

**File:** `lib/skill_to_sandbox/analysis/analyzer.ex`

**Tasks:**

1. Replace the current `additional_file_content/1` logic:
   - Current: Only `.md` files (excluding SKILL.md), up to 5, 4000 chars each
   - New: Use `DependencyRelevantFiles.select_files_for_llm/2` to get files

2. Format output for the prompt:
   ```
   Additional files (templates, code, manifests):
   ---
   File: templates/viewer.html
   ---
   [content, truncated if needed]
   ---
   File: templates/generator_template.js
   ---
   [content]
   ...
   ```

3. For very long files, truncate with clear marker:
   - Prefer keeping top of file (imports)
   - Use `...[truncated, N chars total]` at end

4. Preserve backward compatibility: skills with only .md files should behave as before (perhaps with .md files in the "relevant" set).

**Deliverable:** Updated `build_user_prompt/2` that includes code/HTML/manifest content.

---

### Phase 2: Deterministic Code and CDN Extraction

#### Step 2.1: Implement CDN URL extractor

**File:** `lib/skill_to_sandbox/analysis/code_dependency_extractor.ex` (new module)

**Tasks:**

1. Define regex patterns for common CDN URLs:
   - cdnjs: `cdnjs.cloudflare.com/ajax/libs/([^/]+)/([^/]+)/`
   - unpkg: `unpkg.com/(?:@?[^/]+)(?:@([^/]+))?/`
   - jsdelivr: `cdn.jsdelivr.net/npm/([^/]+)(?:@([^/]+))?/`
   - Add mapping from CDN lib names to npm package names (e.g., `p5.js` → `p5`)

2. Implement `extract_cdn_packages(file_tree)`:
   - Scan all file contents for `<script src="...">` and similar
   - Return `%{npm_packages: %{"p5" => "1.7.0"}}` (or similar structure)

3. Handle version inference:
   - When version is in URL, use it exactly
   - When absent, use `"latest"` or omit

**Deliverable:** `extract_cdn_packages/1` returning package => version map.

---

#### Step 2.2: Implement import/require extractor

**File:** `lib/skill_to_sandbox/analysis/code_dependency_extractor.ex`

**Tasks:**

1. Define patterns for:
   - CommonJS: `require(['"](\@?[^'"]+)['"])`, `require\s*\(\s*['"](\@?[^'"]+)['"]\s*\)`
   - ESM: `import\s+.+\s+from\s+['"](\@?[^'"]+)['"]`, `import\s+['"](\@?[^'"]+)['"]`
   - Python: `import\s+([a-zA-Z0-9_]+)`, `from\s+([a-zA-Z0-9_.]+)\s+import`
   - (Rust, Go, Ruby – optional, lower priority)

2. Map module specifiers to package names:
   - `react` → `react`
   - `@org/package` → `@org/package`
   - Relative paths (`./`, `../`) – skip
   - Built-ins (`fs`, `path`, `os` in Node) – skip

3. Implement `extract_import_packages(file_tree, language)` or `extract_import_packages(file_tree)` that infers language from extension.

4. Return `%{npm_packages: %{"react" => nil}, pip_packages: %{"flask" => nil}}` (no version from imports usually).

**Deliverable:** `extract_import_packages/1` returning package => version (or nil) map, per manager.

---

#### Step 2.3: Integrate extractor into analyzer flow

**File:** `lib/skill_to_sandbox/analysis/analyzer.ex`

**Tasks:**

1. Call `CodeDependencyExtractor` in `analyze/1`:
   - Run `extract_cdn_packages(file_tree)` and `extract_import_packages(file_tree)`
   - Merge results: CDN provides versions; imports provide names

2. Add new prompt section: "Extracted from code (CDN URLs and imports):"
   - List packages and versions found deterministically
   - Instruct LLM: "These were extracted from file contents. Use these exact packages and versions. You may add more if you see additional evidence."

3. Merge logic: After LLM response, merge extracted deps with LLM output:
   - Extracted packages override LLM for version when we have one
   - Extracted packages are always included (don't let LLM drop them)
   - LLM can add packages not in extractor if justified by content

**Deliverable:** Analyzer uses extractor output in prompt and merge.

---

### Phase 3: Parser and Prompt Refinements

#### Step 3.1: Reframe parser output in prompt

**File:** `lib/skill_to_sandbox/analysis/analyzer.ex`

**Tasks:**

1. Change the "Detected tools/frameworks/dependencies" section to:
   ```
   Detected in documentation text (keyword matching – verify against actual code before adding):
   Tools: ...
   Frameworks: ...
   Dependencies: ...
   Only add a package to runtime_deps if you also see evidence in code (import, require, script src, or manifest).
   ```

2. Optionally reduce prominence of parser output when we have extracted deps or manifest deps.

**Deliverable:** Updated prompt text that discourages blind trust of parser.

---

#### Step 3.2: Fix Express false positive in Parser

**File:** `lib/skill_to_sandbox/skills/parser.ex`

**Tasks:**

1. Replace `{~r/\bExpress\b/, "Express"}` with a more specific pattern:
   - Option A: `{~r/\bExpress\.?js\b|require\s*\(\s*['"]express['"]\)|express\s+framework/i, "Express"}`
   - Option B: Remove Express from framework patterns; let LLM infer from code when `require('express')` exists

2. Document the change: "Express was matching the verb 'express'; now requires technical context."

3. Consider a general review: other patterns that might match common English words (e.g., "motion", "field").

**Deliverable:** Updated `@framework_patterns` with safer Express handling.

---

#### Step 3.3: Add p5.js to Parser and CanonicalDeps (optional)

**File:** `lib/skill_to_sandbox/skills/parser.ex`, `lib/skill_to_sandbox/skills/canonical_deps.ex`

**Tasks:**

1. Add to `@dependency_patterns`: `{~r/\bp5\.?js\b/i, "p5.js"}`

2. Add to CanonicalDeps: `"p5.js" => "p5"`

3. Note: With CDN extractor and expanded file content, this becomes redundant but provides belt-and-suspenders for prose-only mentions.

**Deliverable:** Parser can detect p5.js; CanonicalDeps maps to `p5`.

---

### Phase 4: LLM System Prompt Updates

#### Step 4.1: Add version and evidence rules

**File:** `lib/skill_to_sandbox/analysis/analyzer.ex`

**Tasks:**

1. Add to `@system_prompt`:

   ```
   10. VERSION EXTRACTION: When the skill or its template files contain CDN URLs with versions
       (e.g. cdnjs.cloudflare.com/ajax/libs/p5.js/1.7.0/p5.min.js), use that EXACT version in
       runtime_deps. Do not guess or use a different version.

   11. EVIDENCE-BASED PACKAGES: Only add a package to runtime_deps if there is evidence:
       - In manifests (package.json, requirements.txt, etc.)
       - In import/require statements in code files
       - In <script src="..."> CDN URLs in HTML
       The word "express" can mean "to express/convey" (verb) – do NOT add Express.js unless
       you see require('express'), import express, or explicit server/API usage.
   ```

2. Optionally add more "common false positive" examples (e.g., "motion" vs "framer-motion").

**Deliverable:** Updated system prompt with rules 10 and 11.

---

### Phase 5: Testing and Validation

#### Step 5.1: Unit tests for new modules

**Files:** `test/skill_to_sandbox/analysis/dependency_relevant_files_test.exs`, `test/skill_to_sandbox/analysis/code_dependency_extractor_test.exs`

**Tasks:**

1. `DependencyRelevantFiles`:
   - Test `dependency_relevant?/1` for various paths
   - Test `select_files_for_llm/2` with mock file tree, verify order and budget

2. `CodeDependencyExtractor`:
   - Test CDN extraction: file with p5.js 1.7.0 URL → `%{"p5" => "1.7.0"}`
   - Test import extraction: file with `require('react')` → `%{"react" => nil}`
   - Test Python: `import flask` → pip package
   - Test exclusion of relative imports, built-ins

**Deliverable:** Passing unit tests.

---

#### Step 5.2: Integration test with algorithmic-art skill

**File:** `test/skill_to_sandbox/integration/dependency_detection_test.exs` (or extend existing)

**Tasks:**

1. Fetch or fixture the algorithmic-art skill (SKILL.md + templates).

2. Run full pipeline (or Analyzer.analyze) and assert:
   - p5 present with version ^1.7.0 or 1.7.0
   - Express NOT present

3. Optionally add tests for:
   - Skill with package.json – scanner deps win
   - Skill with CDN-only (like algorithmic-art)
   - Skill with mixed manifest + code imports

**Deliverable:** Integration test that validates algorithmic-art case.

---

#### Step 5.3: Regression tests for existing skills

**Tasks:**

1. Run pipeline on 2–3 other skills (e.g., from anthropics/skills repo).

2. Verify no regressions: previously correct deps still correct.

3. Document expected behavior for each test skill.

**Deliverable:** Regression test suite or checklist.

---

## 5. File Change Summary

| File | Action |
|------|--------|
| `lib/skill_to_sandbox/analysis/dependency_relevant_files.ex` | **Create** – File selection for LLM |
| `lib/skill_to_sandbox/analysis/code_dependency_extractor.ex` | **Create** – CDN and import extraction |
| `lib/skill_to_sandbox/analysis/analyzer.ex` | **Modify** – Use new modules, expand prompt, merge extracted deps |
| `lib/skill_to_sandbox/skills/parser.ex` | **Modify** – Fix Express pattern |
| `lib/skill_to_sandbox/skills/canonical_deps.ex` | **Modify** – Add p5.js mapping (optional) |
| `test/skill_to_sandbox/analysis/dependency_relevant_files_test.exs` | **Create** |
| `test/skill_to_sandbox/analysis/code_dependency_extractor_test.exs` | **Create** |
| `test/skill_to_sandbox/integration/dependency_detection_test.exs` | **Create** or extend |

---

## 6. Success Criteria

1. **algorithmic-art skill**: p5 ^1.7.0 (or 1.7.0); Express not present.
2. **No regressions**: Skills with package.json/requirements.txt still produce correct deps.
3. **Deterministic extraction**: CDN URLs and imports are extracted and merged into final spec.
4. **LLM receives code**: HTML and JS/TS/Py files are included in the prompt when relevant.
5. **Parser role reduced**: Parser suggestions no longer blindly drive package inclusion; evidence from code/manifests preferred.

---

## 7. Rollout and Risk Mitigation

- **Feature flag (optional):** Gate "expanded file content" and "code extractor" behind config so they can be disabled if issues arise.
- **Incremental rollout:** Phase 1 first (expand content), validate; then Phase 2 (extractor), etc.
- **Monitoring:** Log when extractor finds packages LLM missed, and when LLM adds packages not in extractor.

---

## 8. Future Enhancements (Out of Scope)

- Support for more languages (Rust, Go, Ruby) in extractor
- Semantic version inference from lockfiles (yarn.lock, package-lock.json)
- Post-LLM validation that drops packages with no evidence in content
- User override: allow manual add/remove of packages in review UI
