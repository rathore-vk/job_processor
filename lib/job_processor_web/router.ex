defmodule JobProcessorWeb.Router do
  @moduledoc """
  HTTP entry point, served by Bandit.

  The body is parsed after `:match`, so unknown routes skip parsing. Parser errors
  are rescued into 413 (over Plug's 8 MB default) and 400 (invalid JSON).
  """

  use Plug.Router
  use Plug.ErrorHandler

  alias JobProcessorWeb.Response
  alias JobProcessorWeb.TaskController

  @parser_opts Plug.Parsers.init(parsers: [:json], pass: ["*/*"], json_decoder: Jason)

  plug Plug.RequestId
  plug Plug.Logger
  plug Plug.Telemetry, event_prefix: [:job_processor, :router]
  plug :match
  plug :parse_body
  plug :dispatch

  post "/tasks" do
    TaskController.create(conn)
  end

  match _ do
    Response.error(conn, :not_found)
  end

  defp parse_body(conn, _opts) do
    Plug.Parsers.call(conn, @parser_opts)
  rescue
    Plug.Parsers.RequestTooLargeError -> halt(Response.error(conn, :body_too_large))
    Plug.Parsers.ParseError -> halt(Response.error(conn, :malformed_json))
  end

  @impl Plug.ErrorHandler
  def handle_errors(conn, %{reason: reason}) do
    Response.error(conn, {:unexpected, reason})
  end
end
