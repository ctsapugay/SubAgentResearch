defmodule SkillToSandbox.Analysis.CodeDependencyExtractorTest do
  @moduledoc """
  Tests for CodeDependencyExtractor: CDN URL and import/require extraction.
  """
  use ExUnit.Case, async: true

  alias SkillToSandbox.Analysis.CodeDependencyExtractor

  describe "extract_cdn_packages/1" do
    test "extracts p5 from cdnjs URL" do
      html = """
      <script src="https://cdnjs.cloudflare.com/ajax/libs/p5.js/1.7.0/p5.min.js"></script>
      """

      result = CodeDependencyExtractor.extract_cdn_packages(%{"viewer.html" => html})

      assert result.npm_packages["p5"] == "1.7.0"
    end
  end

  describe "extract_import_packages/1" do
    test "extracts react from require()" do
      js = "const React = require('react');"
      result = CodeDependencyExtractor.extract_import_packages(%{"app.js" => js})

      assert Map.has_key?(result.npm_packages, "react")
      assert result.npm_packages["react"] == nil
    end

    test "skips relative imports" do
      js = "import './foo'; import '../bar';"
      result = CodeDependencyExtractor.extract_import_packages(%{"app.js" => js})

      refute Map.has_key?(result.npm_packages, "./foo")
      refute Map.has_key?(result.npm_packages, "../bar")
    end

    test "skips Node built-ins" do
      js = "const fs = require('fs');"
      result = CodeDependencyExtractor.extract_import_packages(%{"app.js" => js})

      refute Map.has_key?(result.npm_packages, "fs")
    end

    test "extracts flask from Python import" do
      py = "import flask"
      result = CodeDependencyExtractor.extract_import_packages(%{"app.py" => py})

      assert Map.has_key?(result.pip_packages, "flask")
      assert result.pip_packages["flask"] == nil
    end
  end

  describe "extract_all/1" do
    test "merges CDN and import results" do
      file_tree = %{
        "viewer.html" =>
          "<script src=\"https://cdnjs.cloudflare.com/ajax/libs/p5.js/1.7.0/p5.min.js\"></script>",
        "app.js" => "const React = require('react');"
      }

      result = CodeDependencyExtractor.extract_all(file_tree)

      assert result.npm_packages["p5"] == "1.7.0"
      assert Map.has_key?(result.npm_packages, "react")
    end
  end
end
