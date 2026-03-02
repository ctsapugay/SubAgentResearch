defmodule SkillToSandbox.Skills.PackageValidator do
  @moduledoc """
  Validates that package names exist on npm and PyPI registries.

  Used to strip hallucinated (non-existent) packages from LLM output before
  including them in the sandbox spec. When manifests (package.json, requirements.txt)
  exist, validation is typically skipped since those are trusted. When only LLM
  suggests packages, validation is mandatory.
  """

  require Logger

  defp npm_registry do
    Application.get_env(:skill_to_sandbox, :npm_registry_base, "https://registry.npmjs.org")
  end

  defp pypi_base do
    Application.get_env(:skill_to_sandbox, :pypi_base, "https://pypi.org")
  end

  @doc """
  Validates packages against the appropriate registry.

  Returns `{:ok, valid_packages}` where invalid packages are stripped, or
  `{:ok, valid_packages, removed}` when the caller wants to know what was removed.

  ## Examples

      PackageValidator.validate_packages("npm", %{"react" => "^18.0.0", "fake-pkg-xyz" => "1.0.0"})
      # => {:ok, %{"react" => "^18.0.0"}, ["fake-pkg-xyz"]}

      PackageValidator.validate_packages("pip", %{"flask" => "3.0.0", "nonexistent-pip-pkg" => "1.0"})
      # => {:ok, %{"flask" => "3.0.0"}, ["nonexistent-pip-pkg"]}
  """
  @spec validate_packages(
          manager :: String.t(),
          packages :: %{String.t() => String.t()}
        ) ::
          {:ok, %{String.t() => String.t()}}
          | {:ok, %{String.t() => String.t()}, [String.t()]}
  def validate_packages(_manager, packages) when is_map(packages) and map_size(packages) == 0 do
    {:ok, %{}}
  end

  def validate_packages("npm", packages) when is_map(packages) do
    if validate_enabled?() do
      do_validate_npm(packages)
    else
      {:ok, packages}
    end
  end

  def validate_packages("pip", packages) when is_map(packages) do
    if validate_enabled?() do
      do_validate_pip(packages)
    else
      {:ok, packages}
    end
  end

  def validate_packages(_manager, packages) when is_map(packages) do
    # Unknown manager: return as-is
    {:ok, packages}
  end

  defp validate_enabled? do
    Application.get_env(:skill_to_sandbox, :validate_packages, true)
  end

  defp timeout_ms do
    Application.get_env(:skill_to_sandbox, :validate_packages_timeout_ms, 5_000)
  end

  defp do_validate_npm(packages) do
    timeout = timeout_ms()

    results =
      packages
      |> Task.async_stream(
        fn {name, version} ->
          valid? = npm_package_exists?(name, timeout)
          {name, version, valid?}
        end,
        max_concurrency: 5,
        ordered: false,
        timeout: timeout + 1000
      )
      |> Enum.to_list()

    {valid, removed} =
      Enum.reduce(results, {[], []}, fn
        {:ok, {name, version, true}}, {valid_acc, removed_acc} ->
          {[{name, version} | valid_acc], removed_acc}

        {:ok, {name, _version, false}}, {valid_acc, removed_acc} ->
          Logger.debug("[PackageValidator] Removing invalid npm package: #{name}")
          {valid_acc, [name | removed_acc]}

        {:exit, _}, acc ->
          acc
      end)

    valid_packages = Map.new(valid)

    if removed == [] do
      {:ok, valid_packages}
    else
      {:ok, valid_packages, Enum.reverse(removed)}
    end
  end

  defp npm_package_exists?(name, timeout) do
    url = "#{npm_registry()}/#{URI.encode(name)}/latest"
    opts = [retry: false, receive_timeout: timeout]

    case Req.get(url, opts) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end

  defp do_validate_pip(packages) do
    timeout = timeout_ms()

    results =
      packages
      |> Task.async_stream(
        fn {name, version} ->
          valid? = pypi_package_exists?(name, timeout)
          {name, version, valid?}
        end,
        max_concurrency: 5,
        ordered: false,
        timeout: timeout + 1000
      )
      |> Enum.to_list()

    {valid, removed} =
      Enum.reduce(results, {[], []}, fn
        {:ok, {name, version, true}}, {valid_acc, removed_acc} ->
          {[{name, version} | valid_acc], removed_acc}

        {:ok, {name, _version, false}}, {valid_acc, removed_acc} ->
          Logger.debug("[PackageValidator] Removing invalid pip package: #{name}")
          {valid_acc, [name | removed_acc]}

        {:exit, _}, acc ->
          acc
      end)

    valid_packages = Map.new(valid)

    if removed == [] do
      {:ok, valid_packages}
    else
      {:ok, valid_packages, Enum.reverse(removed)}
    end
  end

  defp pypi_package_exists?(name, timeout) do
    # PyPI uses normalized names in URLs (lowercase, dots/hyphens)
    normalized = name |> String.downcase() |> String.replace(".", "-")
    url = "#{pypi_base()}/pypi/#{URI.encode(normalized)}/json"
    opts = [retry: false, receive_timeout: timeout]

    case Req.get(url, opts) do
      {:ok, %{status: 200}} -> true
      _ -> false
    end
  end
end
