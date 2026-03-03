defmodule SkillToSandbox.Skills.PackageValidatorTest do
  use ExUnit.Case, async: false

  alias SkillToSandbox.Skills.PackageValidator

  setup do
    # Disable validation so we can test with mocked HTTP
    Application.put_env(:skill_to_sandbox, :validate_packages, true)

    bypass = Bypass.open()

    Application.put_env(:skill_to_sandbox, :npm_registry_base, "http://localhost:#{bypass.port}")
    Application.put_env(:skill_to_sandbox, :pypi_base, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.put_env(:skill_to_sandbox, :validate_packages, false)
      Application.delete_env(:skill_to_sandbox, :npm_registry_base)
      Application.delete_env(:skill_to_sandbox, :pypi_base)
    end)

    %{bypass: bypass}
  end

  describe "validate_packages/2" do
    test "returns empty when packages empty" do
      assert {:ok, %{}} = PackageValidator.validate_packages("npm", %{})
    end

    test "strips invalid npm packages (404)", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/react/latest", fn conn ->
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      Bypass.expect(bypass, "GET", "/fake-nonexistent-pkg-xyz999/latest", fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:ok, valid, removed} =
               PackageValidator.validate_packages("npm", %{
                 "react" => "^18.0.0",
                 "fake-nonexistent-pkg-xyz999" => "1.0.0"
               })

      assert valid["react"] == "^18.0.0"
      refute Map.has_key?(valid, "fake-nonexistent-pkg-xyz999")
      assert "fake-nonexistent-pkg-xyz999" in removed
    end

    test "keeps valid npm packages", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/react/latest", fn conn ->
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      Bypass.expect(bypass, "GET", "/vue/latest", fn conn ->
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert {:ok, valid} =
               PackageValidator.validate_packages("npm", %{
                 "react" => "^18.0.0",
                 "vue" => "^3.0.0"
               })

      assert valid["react"] == "^18.0.0"
      assert valid["vue"] == "^3.0.0"
    end

    test "strips invalid pip packages (404)", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/pypi/flask/json", fn conn ->
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      Bypass.expect(bypass, "GET", "/pypi/fake-pip-pkg-xyz999/json", fn conn ->
        Plug.Conn.send_resp(conn, 404, "Not Found")
      end)

      assert {:ok, valid, removed} =
               PackageValidator.validate_packages("pip", %{
                 "flask" => "3.0.0",
                 "fake-pip-pkg-xyz999" => "1.0.0"
               })

      assert valid["flask"] == "3.0.0"
      refute Map.has_key?(valid, "fake-pip-pkg-xyz999")
      assert "fake-pip-pkg-xyz999" in removed
    end

    test "returns ok without removed list when all valid", %{bypass: bypass} do
      Bypass.expect(bypass, "GET", "/react/latest", fn conn ->
        Plug.Conn.send_resp(conn, 200, "{}")
      end)

      assert {:ok, valid} = PackageValidator.validate_packages("npm", %{"react" => "^18.0.0"})
      assert map_size(valid) == 1
    end
  end
end
