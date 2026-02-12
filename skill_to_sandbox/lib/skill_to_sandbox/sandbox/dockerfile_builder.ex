defmodule SkillToSandbox.Sandbox.DockerfileBuilder do
  @moduledoc """
  Generates a Dockerfile from a `%SandboxSpec{}`.

  Supports multiple runtime types (Node.js via npm/yarn/pnpm, Python via pip,
  and generic/unknown). The generated Dockerfile:

  - Uses the smallest appropriate base image (prefer -slim variants)
  - Installs system packages via apt-get
  - Installs language-specific dependencies via the appropriate package manager
  - Sets up the /tools directory with tool scripts and the tool manifest
  - Uses `tail -f /dev/null` as the entrypoint to keep the container alive
    for `docker exec` commands
  """

  alias SkillToSandbox.Analysis.SandboxSpec

  @doc """
  Build a Dockerfile string from a sandbox spec.

  Returns the full Dockerfile content as a string.
  """
  def build(%SandboxSpec{} = spec) do
    [
      base_image_line(spec),
      label_block(spec),
      system_packages_block(spec),
      workdir_line(),
      runtime_deps_block(spec),
      tool_setup_block(),
      env_block(spec),
      entrypoint_line()
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n\n")
    |> Kernel.<>("\n")
  end

  @doc """
  Returns a list of extra files (besides the Dockerfile) that must be present
  in the build context for the generated Dockerfile to build successfully.

  Each entry is `{relative_path, content}`.
  """
  def required_context_files(%SandboxSpec{} = spec) do
    dep_files(spec)
  end

  # -- Private builders --

  defp base_image_line(%{base_image: image}) do
    "FROM #{image}"
  end

  defp label_block(%{skill_id: skill_id}) when not is_nil(skill_id) do
    "# Metadata\n" <>
      "LABEL maintainer=\"skill-to-sandbox\" \\\n" <>
      "      skill_id=\"#{skill_id}\""
  end

  defp label_block(_), do: nil

  defp system_packages_block(%{system_packages: pkgs})
       when is_list(pkgs) and pkgs != [] do
    packages = Enum.join(pkgs, " \\\n        ")

    "# System packages\n" <>
      "RUN apt-get update && \\\n" <>
      "    apt-get install -y --no-install-recommends \\\n" <>
      "    #{packages} && \\\n" <>
      "    rm -rf /var/lib/apt/lists/*"
  end

  defp system_packages_block(_), do: nil

  defp workdir_line, do: "WORKDIR /workspace"

  defp runtime_deps_block(%{runtime_deps: %{"manager" => "npm"}} = spec) do
    node_install = npm_install_command(spec)

    "# Node.js dependencies\n" <>
      "COPY package.json /workspace/package.json\n" <>
      "RUN #{node_install}"
  end

  defp runtime_deps_block(%{runtime_deps: %{"manager" => "yarn"}}) do
    "# Node.js dependencies (yarn)\n" <>
      "COPY package.json /workspace/package.json\n" <>
      "RUN yarn install --production"
  end

  defp runtime_deps_block(%{runtime_deps: %{"manager" => "pnpm"}}) do
    "# Node.js dependencies (pnpm)\n" <>
      "RUN npm install -g pnpm\n" <>
      "COPY package.json /workspace/package.json\n" <>
      "RUN pnpm install --prod"
  end

  defp runtime_deps_block(%{runtime_deps: %{"manager" => "pip"}}) do
    "# Python dependencies\n" <>
      "COPY requirements.txt /workspace/requirements.txt\n" <>
      "RUN pip install --no-cache-dir -r requirements.txt"
  end

  defp runtime_deps_block(%{runtime_deps: %{"manager" => "pip3"}}) do
    "# Python dependencies\n" <>
      "COPY requirements.txt /workspace/requirements.txt\n" <>
      "RUN pip3 install --no-cache-dir -r requirements.txt"
  end

  defp runtime_deps_block(_), do: nil

  defp tool_setup_block do
    "# Tool scripts and manifest\n" <>
      "COPY tools/ /tools/\n" <>
      "RUN chmod +x /tools/*.sh\n" <>
      "COPY tool_manifest.json /workspace/tool_manifest.json\n" <>
      "ENV PATH=\"/tools:$PATH\""
  end

  defp env_block(%{tool_configs: %{"cli" => cli_config}}) when is_map(cli_config) do
    path_additions = Map.get(cli_config, "path_additions", [])

    lines =
      [
        env_line("WORKSPACE_DIR", Map.get(cli_config, "working_dir", "/workspace")),
        env_line("CLI_TIMEOUT", to_string(Map.get(cli_config, "timeout_seconds", 30)))
      ] ++
        if path_additions != [] do
          [env_line("EXTRA_PATH", Enum.join(path_additions, ":"))]
        else
          []
        end

    lines
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      envs -> "# Environment\n" <> Enum.join(envs, "\n")
    end
  end

  defp env_block(_), do: nil

  defp entrypoint_line do
    "# Keep container running for interactive use via docker exec\n" <>
      ~s(CMD ["tail", "-f", "/dev/null"])
  end

  # -- Helpers --

  defp npm_install_command(%{runtime_deps: %{"packages" => pkgs}})
       when map_size(pkgs) > 0 do
    "npm install --production"
  end

  defp npm_install_command(_), do: "npm install --production"

  defp env_line(key, value) when is_binary(value) and value != "" do
    "ENV #{key}=\"#{value}\""
  end

  defp env_line(_, _), do: nil

  # -- Dependency file generation --

  defp dep_files(%{runtime_deps: %{"manager" => manager, "packages" => pkgs}})
       when manager in ["npm", "yarn", "pnpm"] and is_map(pkgs) do
    package_json =
      Jason.encode!(
        %{
          "name" => "sandbox",
          "version" => "1.0.0",
          "private" => true,
          "dependencies" => pkgs
        },
        pretty: true
      )

    [{"package.json", package_json}]
  end

  defp dep_files(%{runtime_deps: %{"manager" => manager, "packages" => pkgs}})
       when manager in ["pip", "pip3"] and is_map(pkgs) do
    requirements =
      pkgs
      |> Enum.map(fn
        {name, version} when is_binary(version) and version != "" ->
          normalized = normalize_python_version(version)
          "#{name}#{normalized}"

        {name, _} ->
          name
      end)
      |> Enum.join("\n")

    [{"requirements.txt", requirements <> "\n"}]
  end

  defp dep_files(_), do: []

  defp normalize_python_version("^" <> version), do: ">=#{version}"
  defp normalize_python_version("~" <> version), do: "~=#{version}"
  defp normalize_python_version("==" <> _ = version), do: version
  defp normalize_python_version(">=" <> _ = version), do: version
  defp normalize_python_version("<=" <> _ = version), do: version
  defp normalize_python_version(">" <> _ = version), do: version
  defp normalize_python_version("<" <> _ = version), do: version
  defp normalize_python_version("~=" <> _ = version), do: version
  defp normalize_python_version(version), do: "==#{version}"
end
