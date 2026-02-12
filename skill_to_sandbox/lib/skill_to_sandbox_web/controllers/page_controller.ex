defmodule SkillToSandboxWeb.PageController do
  use SkillToSandboxWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
