defmodule SkillToSandbox.Repo do
  use Ecto.Repo,
    otp_app: :skill_to_sandbox,
    adapter: Ecto.Adapters.SQLite3
end
