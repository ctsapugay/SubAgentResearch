defmodule SkillToSandbox.Skills.GitHubFetcherTest do
  use ExUnit.Case, async: false

  alias SkillToSandbox.Skills.GitHubFetcher

  setup do
    bypass = Bypass.open()
    Application.put_env(:skill_to_sandbox, :github_raw_base, "http://localhost:#{bypass.port}")
    Application.put_env(:skill_to_sandbox, :github_api_base, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.delete_env(:skill_to_sandbox, :github_raw_base)
      Application.delete_env(:skill_to_sandbox, :github_api_base)
    end)

    %{bypass: bypass}
  end

  describe "fetch/1 with file URL (github.com/blob)" do
    test "returns content for 200 response", %{bypass: bypass} do
      content = "# Agent Browser\n\nSkill content here."

      Bypass.expect(bypass, "GET", "/org/repo/main/skills/agent-browser/SKILL.md", fn conn ->
        Plug.Conn.send_resp(conn, 200, content)
      end)

      assert {:ok, result} =
               GitHubFetcher.fetch(
                 "https://github.com/org/repo/blob/main/skills/agent-browser/SKILL.md"
               )

      assert result.type == :file
      assert result.content == content
      assert result.path == "skills/agent-browser/SKILL.md"
    end

    test "returns :not_found for 404", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/org/repo/main/nonexistent.md", fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:error, :not_found} =
               GitHubFetcher.fetch("https://github.com/org/repo/blob/main/nonexistent.md")
    end

    test "returns :rate_limited for 429", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/org/repo/main/file.md", fn conn ->
        Plug.Conn.send_resp(conn, 429, "Too Many Requests")
      end)

      assert {:error, :rate_limited} =
               GitHubFetcher.fetch("https://github.com/org/repo/blob/main/file.md")
    end
  end

  describe "fetch/1 with raw URL" do
    test "returns content for 200 response", %{bypass: bypass} do
      content = "---\nname: test\n---\n\n# Test"

      Bypass.expect(bypass, "GET", "/owner/repo/main/path/to/SKILL.md", fn conn ->
        Plug.Conn.send_resp(conn, 200, content)
      end)

      assert {:ok, result} =
               GitHubFetcher.fetch(
                 "https://raw.githubusercontent.com/owner/repo/main/path/to/SKILL.md"
               )

      assert result.type == :file
      assert result.content == content
      assert result.path == "path/to/SKILL.md"
    end
  end

  describe "fetch/1 with directory URL" do
    test "returns file_tree with path stripping", %{bypass: bypass} do
      # Commit to get tree SHA
      Bypass.expect(bypass, "GET", "/repos/org/repo/commits/main", fn conn ->
        body = %{
          "commit" => %{"tree" => %{"sha" => "treesha123"}},
          "sha" => "abc123"
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end)

      # Tree with recursive
      Bypass.expect(bypass, "GET", "/repos/org/repo/git/trees/treesha123", fn conn ->
        # Match query string
        assert conn.query_string == "recursive=1"

        body = %{
          "tree" => [
            %{"path" => "skills/agent-browser/SKILL.md", "sha" => "blob1", "type" => "blob"},
            %{
              "path" => "skills/agent-browser/references/commands.md",
              "sha" => "blob2",
              "type" => "blob"
            }
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end)

      # Blob 1
      Bypass.expect(bypass, "GET", "/repos/org/repo/git/blobs/blob1", fn conn ->
        content = Base.encode64("# Agent Browser\n\nMain skill.")
        body = %{"content" => content, "encoding" => "base64"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end)

      # Blob 2
      Bypass.expect(bypass, "GET", "/repos/org/repo/git/blobs/blob2", fn conn ->
        content = Base.encode64("# Commands\n\nReference content.")
        body = %{"content" => content, "encoding" => "base64"}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end)

      url = "https://github.com/org/repo/tree/main/skills/agent-browser"

      assert {:ok, result} = GitHubFetcher.fetch(url)

      assert result.type == :directory
      assert result.root_url == url
      assert result.file_tree["SKILL.md"] == "# Agent Browser\n\nMain skill."
      assert result.file_tree["references/commands.md"] == "# Commands\n\nReference content."
    end

    test "returns :not_found when commit not found", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/repos/org/repo/commits/badref", fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:error, :not_found} =
               GitHubFetcher.fetch("https://github.com/org/repo/tree/badref/skills/agent-browser")
    end

    test "returns :empty_directory when no files under path", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/repos/org/repo/commits/main", fn conn ->
        body = %{"commit" => %{"tree" => %{"sha" => "treesha123"}}}

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end)

      Bypass.expect(bypass, "GET", "/repos/org/repo/git/trees/treesha123", fn conn ->
        # Tree has no blobs under skills/agent-browser (only other paths)
        body = %{
          "tree" => [
            %{"path" => "other/README.md", "sha" => "blob1", "type" => "blob"}
          ]
        }

        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(body))
      end)

      assert {:error, :empty_directory} =
               GitHubFetcher.fetch("https://github.com/org/repo/tree/main/skills/agent-browser")
    end
  end

  describe "fetch/1 URL validation" do
    test "returns :invalid_url for non-GitHub URL" do
      assert {:error, :invalid_url} = GitHubFetcher.fetch("https://example.com/file.md")
    end

    test "returns :invalid_url for non-blob/tree github.com path" do
      # github.com/org/repo without blob or tree
      assert {:error, :invalid_url} = GitHubFetcher.fetch("https://github.com/org/repo")
    end

    test "returns :invalid_url for nil" do
      assert {:error, :invalid_url} = GitHubFetcher.fetch(nil)
    end
  end
end
