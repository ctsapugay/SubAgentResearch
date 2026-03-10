defmodule SkillToSandbox.Skills.CanonicalDepsTest do
  use ExUnit.Case, async: true

  alias SkillToSandbox.Skills.CanonicalDeps

  describe "to_canonical_packages/2" do
    test "maps Framer Motion and Motion to framer-motion" do
      result = CanonicalDeps.to_canonical_packages(["Framer Motion", "Motion"], "npm")
      assert result["framer-motion"] == "latest"
      assert map_size(result) == 1
    end

    test "maps Tailwind variants to tailwindcss" do
      result = CanonicalDeps.to_canonical_packages(["Tailwind CSS", "Tailwind"], "npm")
      assert result["tailwindcss"] == "latest"
      assert map_size(result) == 1
    end

    test "returns empty for unknown names" do
      result = CanonicalDeps.to_canonical_packages(["Unknown Lib", "Some Random Package"], "npm")
      assert result == %{}
    end

    test "returns empty for empty list" do
      assert CanonicalDeps.to_canonical_packages([], "npm") == %{}
    end

    test "maps Playwright and other known deps" do
      result = CanonicalDeps.to_canonical_packages(["Playwright", "DaisyUI", "Vitest"], "npm")
      assert result["playwright"] == "latest"
      assert result["daisyui"] == "latest"
      assert result["vitest"] == "latest"
    end

    test "maps pip packages" do
      result = CanonicalDeps.to_canonical_packages(["Flask", "Django"], "pip")
      assert result["flask"] == nil
      assert result["django"] == nil
    end

    test "returns empty for unknown manager" do
      assert CanonicalDeps.to_canonical_packages(["React"], "cargo") == %{}
    end

    test "maps Puppeteer to puppeteer" do
      result = CanonicalDeps.to_canonical_packages(["Puppeteer"], "npm")
      assert result["puppeteer"] == "latest"
    end

    test "maps Selenium to selenium-webdriver" do
      result = CanonicalDeps.to_canonical_packages(["Selenium"], "npm")
      assert result["selenium-webdriver"] == "latest"
    end

    test "maps WebDriver to selenium-webdriver" do
      result = CanonicalDeps.to_canonical_packages(["WebDriver"], "npm")
      assert result["selenium-webdriver"] == "latest"
    end

    test "maps Playwright Test to @playwright/test" do
      result = CanonicalDeps.to_canonical_packages(["Playwright Test"], "npm")
      assert result["@playwright/test"] == "latest"
    end
  end
end
