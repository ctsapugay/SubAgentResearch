defmodule SkillToSandbox.Sandbox.DockerfileBuilderTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Sandbox.DockerfileBuilder

  # Helper to build a spec struct with the given overrides.
  # We construct the struct directly to avoid needing the database.
  defp build_spec(attrs \\ %{}) do
    defaults = %{
      id: 1,
      skill_id: 1,
      base_image: "node:20-slim",
      system_packages: ["git", "curl", "build-essential"],
      runtime_deps: %{
        "manager" => "npm",
        "packages" => %{"react" => "^18.0.0", "react-dom" => "^18.0.0"}
      },
      tool_configs: %{
        "cli" => %{
          "shell" => "/bin/bash",
          "working_dir" => "/workspace",
          "path_additions" => [],
          "timeout_seconds" => 30
        },
        "web_search" => %{
          "enabled" => true,
          "description" => "Search the web"
        }
      },
      eval_goals: ["Easy: Create a hello world page"],
      dockerfile_content: nil,
      status: "approved"
    }

    struct(SkillToSandbox.Analysis.SandboxSpec, Map.merge(defaults, attrs))
  end

  describe "build/1" do
    test "generates a valid Dockerfile for a Node.js npm spec" do
      spec = build_spec()
      result = DockerfileBuilder.build(spec)

      assert result =~ "FROM node:20-slim"
      assert result =~ "apt-get install -y --no-install-recommends"
      assert result =~ "git"
      assert result =~ "curl"
      assert result =~ "build-essential"
      assert result =~ "WORKDIR /workspace"
      assert result =~ "COPY package.json /workspace/package.json"
      assert result =~ "npm install --omit=dev"
      assert result =~ "COPY tools/ /tools/"
      assert result =~ "chmod +x /tools/*.sh"
      assert result =~ "COPY tool_manifest.json /workspace/tool_manifest.json"
      assert result =~ ~s(CMD ["tail", "-f", "/dev/null"])
    end

    test "generates a valid Dockerfile for a Python pip spec" do
      spec =
        build_spec(%{
          base_image: "python:3.12-slim",
          runtime_deps: %{
            "manager" => "pip",
            "packages" => %{"flask" => "^3.0.0", "requests" => "2.31.0"}
          }
        })

      result = DockerfileBuilder.build(spec)

      assert result =~ "FROM python:3.12-slim"
      assert result =~ "COPY requirements.txt /workspace/requirements.txt"
      assert result =~ "pip install --no-cache-dir -r requirements.txt"
      refute result =~ "package.json"
      refute result =~ "npm install"
    end

    test "generates a valid Dockerfile for yarn" do
      spec =
        build_spec(%{
          runtime_deps: %{
            "manager" => "yarn",
            "packages" => %{"express" => "^4.18.0"}
          }
        })

      result = DockerfileBuilder.build(spec)

      assert result =~ "yarn install --production=true"
      assert result =~ "COPY package.json"
    end

    test "generates a valid Dockerfile for pnpm" do
      spec =
        build_spec(%{
          runtime_deps: %{
            "manager" => "pnpm",
            "packages" => %{"express" => "^4.18.0"}
          }
        })

      result = DockerfileBuilder.build(spec)

      assert result =~ "npm install -g pnpm"
      assert result =~ "pnpm install --prod"
    end

    test "handles empty system packages gracefully" do
      spec = build_spec(%{system_packages: []})
      result = DockerfileBuilder.build(spec)

      refute result =~ "apt-get"
      assert result =~ "FROM node:20-slim"
      assert result =~ ~s(CMD ["tail", "-f", "/dev/null"])
    end

    test "handles nil system packages gracefully" do
      spec = build_spec(%{system_packages: nil})
      result = DockerfileBuilder.build(spec)

      refute result =~ "apt-get"
    end

    test "handles nil runtime deps gracefully" do
      spec = build_spec(%{runtime_deps: nil})
      result = DockerfileBuilder.build(spec)

      refute result =~ "package.json"
      refute result =~ "requirements.txt"
      refute result =~ "npm"
      refute result =~ "pip"
      # But the rest should still be present
      assert result =~ "FROM node:20-slim"
      assert result =~ "COPY tools/ /tools/"
      assert result =~ ~s(CMD ["tail", "-f", "/dev/null"])
    end

    test "handles unknown package manager gracefully" do
      spec = build_spec(%{runtime_deps: %{"manager" => "cargo", "packages" => %{}}})
      result = DockerfileBuilder.build(spec)

      refute result =~ "cargo"
      refute result =~ "package.json"
      refute result =~ "requirements.txt"
    end

    test "always includes the keep-alive CMD" do
      spec = build_spec()
      result = DockerfileBuilder.build(spec)

      assert result =~ ~s(CMD ["tail", "-f", "/dev/null"])
    end

    test "always includes tool setup" do
      spec = build_spec()
      result = DockerfileBuilder.build(spec)

      assert result =~ "COPY tools/ /tools/"
      assert result =~ "chmod +x /tools/*.sh"
      assert result =~ "COPY tool_manifest.json /workspace/tool_manifest.json"
      assert result =~ ~s(ENV PATH="/tools:$PATH")
    end

    test "includes label with skill_id" do
      spec = build_spec(%{skill_id: 42})
      result = DockerfileBuilder.build(spec)

      assert result =~ ~s(skill_id="42")
    end

    test "includes environment variables from CLI tool config" do
      spec = build_spec()
      result = DockerfileBuilder.build(spec)

      assert result =~ ~s(ENV WORKSPACE_DIR="/workspace")
      assert result =~ ~s(ENV CLI_TIMEOUT="30")
    end

    test "includes extra path from CLI tool config path_additions" do
      spec =
        build_spec(%{
          tool_configs: %{
            "cli" => %{
              "shell" => "/bin/bash",
              "working_dir" => "/workspace",
              "path_additions" => ["/usr/local/go/bin", "/home/user/.cargo/bin"],
              "timeout_seconds" => 60
            },
            "web_search" => %{"enabled" => true}
          }
        })

      result = DockerfileBuilder.build(spec)

      assert result =~ ~s(ENV EXTRA_PATH="/usr/local/go/bin:/home/user/.cargo/bin")
      assert result =~ ~s(ENV CLI_TIMEOUT="60")
    end

    test "ends with a trailing newline" do
      spec = build_spec()
      result = DockerfileBuilder.build(spec)

      assert String.ends_with?(result, "\n")
    end
  end

  describe "required_context_files/1" do
    test "generates package.json for npm specs" do
      spec = build_spec()
      files = DockerfileBuilder.required_context_files(spec)

      assert [{"package.json", content}] = files
      decoded = Jason.decode!(content)
      assert decoded["name"] == "sandbox"
      assert decoded["dependencies"]["react"] == "^18.0.0"
      assert decoded["dependencies"]["react-dom"] == "^18.0.0"
    end

    test "generates package.json for yarn specs" do
      spec =
        build_spec(%{
          runtime_deps: %{
            "manager" => "yarn",
            "packages" => %{"express" => "^4.18.0"}
          }
        })

      files = DockerfileBuilder.required_context_files(spec)

      assert [{"package.json", content}] = files
      decoded = Jason.decode!(content)
      assert decoded["dependencies"]["express"] == "^4.18.0"
    end

    test "generates requirements.txt for pip specs" do
      spec =
        build_spec(%{
          base_image: "python:3.12-slim",
          runtime_deps: %{
            "manager" => "pip",
            "packages" => %{"flask" => "3.0.0", "requests" => "^2.31.0"}
          }
        })

      files = DockerfileBuilder.required_context_files(spec)

      assert [{"requirements.txt", content}] = files
      # Version normalization: "3.0.0" -> "==3.0.0", "^2.31.0" -> ">=2.31.0"
      assert content =~ "flask==3.0.0"
      assert content =~ "requests>=2.31.0"
    end

    test "returns empty list for unknown managers" do
      spec = build_spec(%{runtime_deps: %{"manager" => "cargo", "packages" => %{}}})
      assert DockerfileBuilder.required_context_files(spec) == []
    end

    test "returns empty list for nil runtime deps" do
      spec = build_spec(%{runtime_deps: nil})
      assert DockerfileBuilder.required_context_files(spec) == []
    end
  end
end
