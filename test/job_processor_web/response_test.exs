defmodule JobProcessorWeb.ResponseTest do
  use JobProcessorWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  alias JobProcessor.Tasks.Task
  alias JobProcessorWeb.Response

  doctest JobProcessorWeb.Response

  defp negotiate(accept) do
    conn(:post, "/tasks") |> put_req_header("accept", accept) |> Response.negotiate()
  end

  describe "negotiate/1" do
    test "an empty or blank header means JSON" do
      assert negotiate("") == {:ok, :json}
      assert negotiate("  ") == {:ok, :json}
      assert negotiate(" , ") == {:ok, :json}
    end

    test "wildcards map to a format" do
      assert negotiate("*/*") == {:ok, :json}
      assert negotiate("application/*") == {:ok, :json}
      assert negotiate("text/*") == {:ok, :text}
    end

    test "the first supported type wins" do
      assert negotiate("text/plain, application/json") == {:ok, :text}
      assert negotiate("application/json, text/plain") == {:ok, :json}
    end

    test "unsupported types are skipped in favour of a later supported one" do
      assert negotiate("application/xml, text/html, text/plain") == {:ok, :text}
      assert negotiate("image/png, */*") == {:ok, :json}
    end

    test "is case-insensitive and tolerates whitespace" do
      assert negotiate("  TEXT/Plain  ") == {:ok, :text}
      assert negotiate("Application/JSON;charset=utf-8") == {:ok, :json}
    end

    test "ignores quality values rather than ranking by them" do
      assert negotiate("text/plain;q=0.1, application/json;q=1.0") == {:ok, :text}
    end

    test "refuses when no listed type is supported" do
      assert negotiate("application/xml, text/html") == {:error, :not_acceptable}
    end
  end

  describe "tasks/3" do
    setup do
      tasks = [
        %Task{name: "build", command: "make"},
        %Task{name: "test", command: "mix test", requires: ["build"]}
      ]

      %{tasks: tasks}
    end

    test "renders JSON with only name and command, in the given order", %{tasks: tasks} do
      conn = Response.tasks(conn(:post, "/tasks"), :json, tasks)

      assert json_response(conn, 200) == %{
               "tasks" => [
                 %{"name" => "build", "command" => "make"},
                 %{"name" => "test", "command" => "mix test"}
               ]
             }
    end

    test "renders a bash script, one command per line", %{tasks: tasks} do
      conn = Response.tasks(conn(:post, "/tasks"), :text, tasks)

      assert text_response(conn, 200) == "#!/usr/bin/env bash\n\nmake\nmix test\n"
    end

    test "renders an empty list" do
      assert json_response(Response.tasks(conn(:post, "/tasks"), :json, []), 200) == %{
               "tasks" => []
             }

      assert text_response(Response.tasks(conn(:post, "/tasks"), :text, []), 200) ==
               "#!/usr/bin/env bash\n\n\n"
    end

    test "outputs commands verbatim, without escaping" do
      tasks = [%Task{name: "a", command: ~s(echo "it's $HOME" > /tmp/x && cat /tmp/x)}]

      assert text_response(Response.tasks(conn(:post, "/tasks"), :text, tasks), 200) ==
               ~s(#!/usr/bin/env bash\n\necho "it's $HOME" > /tmp/x && cat /tmp/x\n)

      assert %{"tasks" => [%{"command" => ~s(echo "it's $HOME" > /tmp/x && cat /tmp/x)}]} =
               json_response(Response.tasks(conn(:post, "/tasks"), :json, tasks), 200)
    end
  end

  describe "error/2" do
    for {reason, status, message} <- [
          {{:circular_dependency, "a"}, 422, "Tasks contain a circular dependency involving a"},
          {{:missing_dependency, "b"}, 422, "Task depends on non-existent task: b"},
          {{:duplicate_task, "c"}, 422, "Duplicate task name: c"},
          {:body_too_large, 413, "Request body is too large"},
          {{:invalid_task, 2}, 400,
           "Invalid task at index 2. Each task requires string 'name' and 'command', " <>
             "plus an optional 'requires' list of strings"},
          {:invalid_payload, 400, ~s(Invalid request body. Expected {"tasks": [...]})},
          {:malformed_json, 400, "Request body is not valid JSON"},
          {:not_acceptable, 406,
           "Unsupported Accept header. Supported: application/json, text/plain"},
          {:not_found, 404, "Not found"}
        ] do
      test "maps #{inspect(reason)} to #{status}" do
        conn = Response.error(conn(:post, "/tasks"), unquote(Macro.escape(reason)))

        assert json_response(conn, unquote(status)) == %{"error" => unquote(message)}
      end
    end

    test "hides unexpected errors behind a 500 and logs them" do
      log =
        capture_log(fn ->
          conn = Response.error(conn(:post, "/tasks"), {:unexpected, :boom})

          assert json_response(conn, 500) == %{"error" => "Internal server error"}
        end)

      assert log =~ "Unhandled error for POST /tasks: :boom"
    end

    test "raises on a reason it does not know" do
      assert_raise FunctionClauseError, fn ->
        Response.error(conn(:post, "/tasks"), :something_else)
      end
    end
  end
end
