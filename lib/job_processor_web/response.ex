defmodule JobProcessorWeb.Response do
  @moduledoc """
  Renders results and errors as HTTP responses.

  The one place a domain error is mapped to a status code.
  """

  import Plug.Conn

  require Logger

  alias JobProcessor.Tasks.Task

  @type format :: :json | :text

  @doc """
  Picks a format from the `Accept` header.

  The first supported type wins. A missing, empty or wildcard header means JSON.

  ## Examples

      iex> Plug.Test.conn(:post, "/tasks") |> Response.negotiate()
      {:ok, :json}

      iex> Plug.Test.conn(:post, "/tasks")
      ...> |> Plug.Conn.put_req_header("accept", "text/plain")
      ...> |> Response.negotiate()
      {:ok, :text}

  Parameters like `q=` are ignored, and an unsupported type is refused:

      iex> Plug.Test.conn(:post, "/tasks")
      ...> |> Plug.Conn.put_req_header("accept", "text/plain; q=0.9")
      ...> |> Response.negotiate()
      {:ok, :text}

      iex> Plug.Test.conn(:post, "/tasks")
      ...> |> Plug.Conn.put_req_header("accept", "application/xml")
      ...> |> Response.negotiate()
      {:error, :not_acceptable}

  """
  @spec negotiate(Plug.Conn.t()) :: {:ok, format()} | {:error, :not_acceptable}
  def negotiate(conn) do
    conn
    |> get_req_header("accept")
    |> List.first("")
    |> String.split(",")
    |> Enum.map(&media_type/1)
    |> Enum.reject(&(&1 == ""))
    |> case do
      [] -> {:ok, :json}
      types -> first_supported(types)
    end
  end

  @doc """
  Renders sorted tasks as JSON or a bash script. Commands are output verbatim.
  """
  @spec tasks(Plug.Conn.t(), format(), [Task.t()]) :: Plug.Conn.t()
  def tasks(conn, :json, tasks) do
    json(conn, 200, %{tasks: Enum.map(tasks, &%{name: &1.name, command: &1.command})})
  end

  def tasks(conn, :text, tasks) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, bash_script(tasks))
  end

  @doc """
  Renders an error as JSON with the matching status code.
  """
  @spec error(Plug.Conn.t(), term()) :: Plug.Conn.t()
  def error(conn, {:unexpected, reason}) do
    Logger.error("Unhandled error for #{conn.method} #{conn.request_path}: #{inspect(reason)}")

    json(conn, 500, %{error: "Internal server error"})
  end

  def error(conn, reason) do
    {status, message} = describe(reason)

    json(conn, status, %{error: message})
  end

  # 422, not 400: the tasks are well-formed, there is just no valid order.
  defp describe({:circular_dependency, name}) do
    {422, "Tasks contain a circular dependency involving #{name}"}
  end

  defp describe({:missing_dependency, name}),
    do: {422, "Task depends on non-existent task: #{name}"}

  defp describe({:duplicate_task, name}), do: {422, "Duplicate task name: #{name}"}

  defp describe(:body_too_large), do: {413, "Request body is too large"}

  defp describe({:invalid_task, index}) do
    {400,
     "Invalid task at index #{index}. Each task requires string 'name' and 'command', " <>
       "plus an optional 'requires' list of strings"}
  end

  defp describe(:invalid_payload), do: {400, "Invalid request body. Expected {\"tasks\": [...]}"}
  defp describe(:malformed_json), do: {400, "Request body is not valid JSON"}

  defp describe(:not_acceptable),
    do: {406, "Unsupported Accept header. Supported: application/json, text/plain"}

  defp describe(:not_found), do: {404, "Not found"}

  defp json(conn, status, body) do
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Jason.encode_to_iodata!(body))
  end

  defp bash_script(tasks) do
    "#!/usr/bin/env bash\n\n" <> Enum.map_join(tasks, "\n", & &1.command) <> "\n"
  end

  defp first_supported(types) do
    case Enum.find_value(types, &format_for/1) do
      nil -> {:error, :not_acceptable}
      format -> {:ok, format}
    end
  end

  defp media_type(part) do
    part |> String.split(";") |> hd() |> String.trim() |> String.downcase()
  end

  defp format_for("application/json"), do: :json
  defp format_for("application/*"), do: :json
  defp format_for("text/plain"), do: :text
  defp format_for("text/*"), do: :text
  defp format_for("*/*"), do: :json
  defp format_for(_other), do: nil
end
