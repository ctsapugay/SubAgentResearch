defmodule SkillToSandbox.Analysis.CodeDependencyExtractor do
  @moduledoc """
  Deterministically extracts package dependencies from file contents:
  - CDN URLs in <script src="..."> tags (cdnjs, unpkg, jsdelivr)
  - Import/require statements in JS/TS and Python

  Returns %{npm_packages: %{}, pip_packages: %{}} suitable for merging with
  LLM/scanner output. Extracted packages with versions override LLM; extracted
  packages are always included.
  """

  # CDN patterns: cdnjs, unpkg, jsdelivr
  # cdnjs: cdnjs.cloudflare.com/ajax/libs/{lib}/{version}/
  @cdnjs_re ~r/cdnjs\.cloudflare\.com\/ajax\/libs\/([^\/]+)\/([^\/]+)\//
  # unpkg: unpkg.com/package@version/ or unpkg.com/package/
  @unpkg_re ~r/unpkg\.com\/(@?[^\/]+)(?:@([^\/\s"']+))?\//
  # jsdelivr: cdn.jsdelivr.net/npm/package@version/ or cdn.jsdelivr.net/npm/package/
  @jsdelivr_re ~r/cdn\.jsdelivr\.net\/npm\/(@?[^\/]+)(?:@([^\/\s"']+))?\//

  # CDN lib name -> npm package name
  @cdn_to_npm %{
    "p5.js" => "p5",
    "p5.min.js" => "p5",
    "p5" => "p5",
    "react" => "react",
    "react-dom" => "react-dom",
    "vue" => "vue",
    "jquery" => "jquery",
    "three.js" => "three",
    "three" => "three",
    "d3" => "d3",
    "bootstrap" => "bootstrap",
    "axios" => "axios",
    "lodash" => "lodash",
    "moment" => "moment",
    "chart.js" => "chart.js",
    "chartjs" => "chart.js"
  }

  # Node built-ins to skip
  @node_builtins ~w(
    assert buffer child_process cluster crypto dgram dns events fs http https
    net os path process punycode querystring readline stream string_decoder
    timers tty url util v8 vm zlib
  )

  @doc """
  Extracts packages from CDN URLs in file contents (<script src="...">).

  Patterns: cdnjs.cloudflare.com, unpkg.com, cdn.jsdelivr.net/npm/
  Maps CDN lib names to npm (e.g. "p5.js" -> "p5"). When version is in URL, use it;
  when absent use "latest".

  Returns %{npm_packages: %{"p5" => "1.7.0"}, pip_packages: %{}}.
  """
  def extract_cdn_packages(file_tree) when is_map(file_tree) do
    results =
      file_tree
      |> Enum.flat_map(fn {_path, content} -> scan_cdn_content(content) end)
      |> Enum.uniq()
      |> Enum.reduce(%{}, fn {name, version}, acc ->
        Map.put(acc, name, version || "latest")
      end)

    %{
      npm_packages: results,
      pip_packages: %{}
    }
  end

  def extract_cdn_packages(_), do: %{npm_packages: %{}, pip_packages: %{}}

  defp scan_cdn_content(content) when not is_binary(content), do: []

  defp scan_cdn_content(content) do
    # Find script src URLs
    script_srcs =
      Regex.scan(~r/<script[^>]*\ssrc\s*=\s*["']([^"']+)["'][^>]*>/i, content,
        capture: :all_but_first
      )

    urls = Enum.flat_map(script_srcs, & &1)

    Enum.flat_map(urls, &extract_from_url/1)
  end

  defp extract_from_url(url) do
    cond do
      match = Regex.run(@cdnjs_re, url) -> extract_cdnjs_match(match)
      match = Regex.run(@unpkg_re, url) -> extract_unpkg_jsdelivr_match(match)
      match = Regex.run(@jsdelivr_re, url) -> extract_unpkg_jsdelivr_match(match)
      true -> []
    end
  end

  defp extract_cdnjs_match([_, lib_raw, version]) do
    lib = normalize_cdn_lib_name(lib_raw)
    npm_name = Map.get(@cdn_to_npm, lib, lib)
    [{npm_name, version}]
  end

  defp extract_unpkg_jsdelivr_match([_, pkg_raw, version]) do
    pkg = (pkg_raw || "") |> String.trim()

    if pkg == "" do
      []
    else
      npm_name = Map.get(@cdn_to_npm, String.downcase(pkg), pkg)
      [{npm_name, version}]
    end
  end

  defp normalize_cdn_lib_name(lib) when is_binary(lib) do
    lib
    |> String.downcase()
    |> String.trim()
  end

  @doc """
  Extracts packages from import/require statements. Infers language from file extension.

  JS/TS: require(['"](@?[^'"]+)['"]), import .+ from ['"](@?[^'"]+)['"]
  Python: import ([a-zA-Z0-9_]+), from ([a-zA-Z0-9_.]+) import

  Skips: relative paths (./, ../), Node built-ins (fs, path, os, etc.)

  Returns %{npm_packages: %{"react" => nil}, pip_packages: %{"flask" => nil}}.
  """
  def extract_import_packages(file_tree) when is_map(file_tree) do
    npm = extract_js_imports(file_tree)
    pip = extract_python_imports(file_tree)

    %{
      npm_packages: npm,
      pip_packages: pip
    }
  end

  def extract_import_packages(_), do: %{npm_packages: %{}, pip_packages: %{}}

  defp extract_js_imports(file_tree) do
    js_extensions = ~w(.js .ts .jsx .tsx .mjs .cjs)

    file_tree
    |> Enum.filter(fn {path, _} ->
      ext = Path.extname(path)
      ext in js_extensions
    end)
    |> Enum.flat_map(fn {_path, content} -> scan_js_imports(content) end)
    |> Enum.uniq()
    |> Enum.reject(&skip_npm_package?/1)
    |> Map.new(fn pkg -> {pkg, nil} end)
  end

  defp scan_js_imports(content) when not is_binary(content), do: []

  defp scan_js_imports(content) do
    # require('pkg') or require("pkg")
    require_matches =
      Regex.scan(~r/require\s*\(\s*['"]([^'"]+)['"]\s*\)/, content, capture: :all_but_first)

    # import x from 'pkg' / import "pkg" / import { x } from "pkg"
    import_from_matches =
      Regex.scan(~r/import\s+(?:[\w*{}\s,]+\s+from\s+)?['"]([^'"]+)['"]/, content,
        capture: :all_but_first
      )

    # import 'pkg' (side-effect import)
    import_side_matches =
      Regex.scan(~r/import\s+['"]([^'"]+)['"]/, content, capture: :all_but_first)

    all =
      (require_matches ++ import_from_matches ++ import_side_matches)
      |> List.flatten()
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    Enum.uniq(all)
  end

  defp skip_npm_package?(spec) do
    # Skip relative paths
    # Skip Node built-ins
    # Skip node: prefix (Node built-in)
    String.starts_with?(spec, ".") or
      spec in @node_builtins or
      String.starts_with?(spec, "node:")
  end

  defp extract_python_imports(file_tree) do
    file_tree
    |> Enum.filter(fn {path, _} -> Path.extname(path) == ".py" end)
    |> Enum.flat_map(fn {_path, content} -> scan_python_imports(content) end)
    |> Enum.uniq()
    |> Enum.reject(&skip_pip_package?/1)
    |> Map.new(fn pkg -> {pkg, nil} end)
  end

  defp scan_python_imports(content) when not is_binary(content), do: []

  defp scan_python_imports(content) do
    # import foo
    import_matches = Regex.scan(~r/import\s+([a-zA-Z0-9_]+)/, content, capture: :all_but_first)
    # from foo.bar import ...
    from_matches =
      Regex.scan(~r/from\s+([a-zA-Z0-9_.]+)\s+import/, content, capture: :all_but_first)

    all =
      (import_matches ++ from_matches)
      |> List.flatten()
      |> Enum.map(&extract_top_level_module/1)
      |> Enum.reject(&is_nil/1)

    Enum.uniq(all)
  end

  defp extract_top_level_module(module) when is_binary(module) do
    # "flask" -> "flask", "flask.ext" -> "flask", "os.path" -> "os" (stdlib), "numpy.linalg" -> "numpy"
    top = module |> String.split(".") |> List.first()
    if top != "", do: top, else: nil
  end

  defp skip_pip_package?(name) when is_binary(name) do
    # Stdlib we don't want to add as pip packages
    name in ~w(os sys math re json csv collections functools itertools pathlib
               argparse logging unittest typing dataclasses io unittest
               subprocess shutil tempfile datetime)
  end

  @doc """
  Merges CDN and import extraction. Returns unified %{npm_packages: %{}, pip_packages: %{}}.

  CDN provides versions when available; imports provide package names (version nil).
  Duplicates: CDN version overrides import's nil.
  """
  def extract_all(file_tree) when is_map(file_tree) do
    cdn = extract_cdn_packages(file_tree)
    imports = extract_import_packages(file_tree)

    npm =
      Map.merge(
        Map.get(imports, :npm_packages, %{}),
        Map.get(cdn, :npm_packages, %{})
      )

    pip = Map.get(imports, :pip_packages, %{})

    %{
      npm_packages: npm,
      pip_packages: pip
    }
  end

  def extract_all(_), do: %{npm_packages: %{}, pip_packages: %{}}
end
