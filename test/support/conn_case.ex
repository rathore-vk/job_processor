defmodule JobProcessorWeb.ConnCase do
  @moduledoc """
  Calls `JobProcessorWeb.Router` directly: the full plug pipeline, no socket.
  """

  use ExUnit.CaseTemplate

  import ExUnit.Assertions

  @router JobProcessorWeb.Router
  @router_opts JobProcessorWeb.Router.init([])

  using do
    quote do
      import Plug.Conn
      import Plug.Test
      import JobProcessorWeb.ConnCase
    end
  end

  @doc "Sends a built conn through the full router pipeline."
  @spec call(Plug.Conn.t()) :: Plug.Conn.t()
  def call(conn), do: @router.call(conn, @router_opts)

  @doc "Asserts the status and JSON content type, then decodes the body."
  @spec json_response(Plug.Conn.t(), non_neg_integer()) :: term()
  def json_response(conn, status) do
    assert conn.status == status
    assert content_type(conn) =~ "application/json"

    Jason.decode!(conn.resp_body)
  end

  @doc "Asserts the status and `text/plain` content type, then returns the body."
  @spec text_response(Plug.Conn.t(), non_neg_integer()) :: binary()
  def text_response(conn, status) do
    assert conn.status == status
    assert content_type(conn) =~ "text/plain"

    conn.resp_body
  end

  defp content_type(conn) do
    conn |> Plug.Conn.get_resp_header("content-type") |> List.first("")
  end
end
