defmodule SkillToSandbox.Agent.PromptBuilderTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Agent.PromptBuilder

  describe "build/1" do
    test "empty map returns base instructions containing key sentinel phrases" do
      result = PromptBuilder.build(%{})
      assert result =~ "You are an AI agent"
      assert result =~ "DONE"
      assert result =~ "STUCK"
    end

    test "npx tool extracted correctly" do
      result =
        PromptBuilder.build(%{
          "frontmatter" => %{"allowed-tools" => "Bash(npx agent-browser:*)"}
        })

      assert result =~ "npx agent-browser"
    end

    test "bare tool extracted" do
      result =
        PromptBuilder.build(%{
          "frontmatter" => %{"allowed-tools" => "Bash(my-tool:*)"}
        })

      assert result =~ "my-tool"
    end

    test "npx preferred over bare when both present" do
      result =
        PromptBuilder.build(%{
          "frontmatter" => %{
            "allowed-tools" => "Bash(npx agent-browser:*), Bash(agent-browser:*)"
          }
        })

      assert result =~ "npx agent-browser"
      refute result =~ "  - agent-browser → invoke as: agent-browser"
    end

    test "no frontmatter key returns base instructions without tools section" do
      result = PromptBuilder.build(%{"name" => "test"})
      refute result =~ "This skill's tools"
    end

    test "self-correction instruction present in base prompt" do
      result = PromptBuilder.build(%{})
      assert result =~ "do not retry"
    end

    test "no $ prefix instruction present in base prompt" do
      result = PromptBuilder.build(%{})
      assert result =~ "$ prefix" or result =~ "No $ prefix"
    end
  end
end
