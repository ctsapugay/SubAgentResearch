defmodule SkillToSandbox.Skills.CanonicalDeps do
  @moduledoc """
  Maps parser-detected human-readable dependency names to canonical npm/PyPI package names.

  Used when no manifests exist: the parser produces names like "Framer Motion" or "Motion",
  and this module yields exact registry names (e.g. "framer-motion") so we avoid LLM guessing.
  """

  # Maps human names from Parser @dependency_patterns to canonical npm package names
  @canonical_npm %{
    "Motion" => "framer-motion",
    "Motion library" => "framer-motion",
    "Framer Motion" => "framer-motion",
    "Tailwind CSS" => "tailwindcss",
    "Tailwind" => "tailwindcss",
    "DaisyUI" => "daisyui",
    "Chakra UI" => "@chakra-ui/react",
    "Shadcn" => "tailwindcss",
    "Axios" => "axios",
    "Redux" => "redux",
    "Zustand" => "zustand",
    "Jotai" => "jotai",
    "Vite" => "vite",
    "Webpack" => "webpack",
    "PostCSS" => "postcss",
    "ESLint" => "eslint",
    "Prettier" => "prettier",
    "Jest" => "jest",
    "Vitest" => "vitest",
    "Playwright" => "playwright",
    "Cypress" => "cypress",
    "Storybook" => "@storybook/react",
    "Three.js" => "three",
    "D3.js" => "d3",
    "GSAP" => "gsap",
    "Lottie" => "lottie-react"
  }

  @default_npm_version "latest"
  @default_pip_version nil

  @doc """
  Converts parser `mentioned_dependencies` (human names) to canonical package map.

  Only includes packages we have explicit mappings for. Returns
  `%{canonical_name => version}`.

  ## Examples

      CanonicalDeps.to_canonical_packages(["Framer Motion", "React", "Unknown Lib"], "npm")
      # => %{"framer-motion" => "latest"}
      # "React" is a framework, not in our dep map; "Unknown Lib" has no mapping

      CanonicalDeps.to_canonical_packages(["Playwright", "Motion"], "npm")
      # => %{"playwright" => "latest", "framer-motion" => "latest"}
  """
  @spec to_canonical_packages(mentioned_dependencies :: [String.t()], manager :: String.t()) ::
          %{String.t() => String.t() | nil}
  def to_canonical_packages(mentioned, "npm") when is_list(mentioned) do
    mentioned
    |> Enum.uniq()
    |> Enum.map(&lookup_npm/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn {canonical, _} -> {canonical, @default_npm_version} end)
  end

  def to_canonical_packages(mentioned, "pip") when is_list(mentioned) do
    # Few parser dependency patterns map to pip; extend as needed
    mentioned
    |> Enum.uniq()
    |> Enum.map(&lookup_pip/1)
    |> Enum.reject(&is_nil/1)
    |> Map.new(fn {canonical, _} -> {canonical, @default_pip_version} end)
  end

  def to_canonical_packages(_mentioned, _manager), do: %{}

  defp lookup_npm(human_name) when is_binary(human_name) do
    trimmed = String.trim(human_name)

    case Map.get(@canonical_npm, trimmed) do
      nil -> nil
      canonical -> {canonical, @default_npm_version}
    end
  end

  defp lookup_pip(human_name) when is_binary(human_name) do
    # Parser dependency patterns are mostly npm; add pip mappings as needed
    trimmed = String.trim(human_name)

    pip_map = %{
      "Flask" => "flask",
      "Django" => "django",
      "FastAPI" => "fastapi",
      "Requests" => "requests",
      "NumPy" => "numpy",
      "Pandas" => "pandas",
      "Pytest" => "pytest"
    }

    case Map.get(pip_map, trimmed) do
      nil -> nil
      canonical -> {canonical, @default_pip_version}
    end
  end
end
