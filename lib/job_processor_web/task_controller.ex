defmodule JobProcessorWeb.TaskController do
  @moduledoc """
  `POST /tasks` — returns the tasks in a valid execution order.
  """

  alias JobProcessor.Tasks
  alias JobProcessorWeb.Response

  @doc """
  Negotiates the format, sorts the tasks and renders the result.
  """
  @spec create(Plug.Conn.t()) :: Plug.Conn.t()
  def create(conn) do
    with {:ok, format} <- Response.negotiate(conn),
         {:ok, tasks} <- fetch_tasks(conn),
         {:ok, sorted} <- Tasks.sort_tasks(tasks) do
      Response.tasks(conn, format, sorted)
    else
      {:error, reason} -> Response.error(conn, reason)
    end
  end

  defp fetch_tasks(%Plug.Conn{body_params: %{"tasks" => tasks}}) when is_list(tasks),
    do: {:ok, tasks}

  defp fetch_tasks(%Plug.Conn{}), do: {:error, :invalid_payload}
end
