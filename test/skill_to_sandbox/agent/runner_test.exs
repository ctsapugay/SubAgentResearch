defmodule SkillToSandbox.Agent.RunnerTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Agent.Runner

  describe "strip_command/1" do
    test "bare command passes through unchanged" do
      assert Runner.strip_command("ls /workspace") == "ls /workspace"
    end

    test "leading $ prefix stripped" do
      assert Runner.strip_command("$ ls /workspace") == "ls /workspace"
    end

    test "leading $\\t prefix stripped" do
      assert Runner.strip_command("$\tls /workspace") == "ls /workspace"
    end

    test "bash fence stripped" do
      assert Runner.strip_command("```bash\nls /workspace\n```") == "ls /workspace"
    end

    test "generic fence stripped" do
      assert Runner.strip_command("```\nnode --version\n```") == "node --version"
    end

    test "sh fence stripped" do
      assert Runner.strip_command("```sh\necho hello\n```") == "echo hello"
    end

    test "$ prefix inside fence stripped" do
      assert Runner.strip_command("```bash\n$ head -n 5 file\n```") == "head -n 5 file"
    end

    test "surrounding whitespace trimmed" do
      assert Runner.strip_command("  echo hello  ") == "echo hello"
    end

    test "DONE signal preserved" do
      assert Runner.strip_command("DONE") == "DONE"
    end

    test "STUCK signal preserved" do
      assert Runner.strip_command("STUCK") == "STUCK"
    end
  end
end
