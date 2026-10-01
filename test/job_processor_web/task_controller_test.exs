defmodule JobProcessorWeb.TaskControllerTest do
  use JobProcessorWeb.ConnCase, async: true

  # Sends real JSON, so `Plug.Parsers` always runs.
  defp post_tasks(tasks, accept \\ "application/json") do
    post_body(Jason.encode!(%{"tasks" => tasks}), accept)
  end

  defp post_body(body, accept \\ "application/json") do
    :post
    |> conn("/tasks", body)
    |> put_req_header("content-type", "application/json")
    |> put_accept(accept)
    |> call()
  end

  defp put_accept(conn, nil), do: conn
  defp put_accept(conn, accept), do: put_req_header(conn, "accept", accept)

  describe "POST /tasks" do
    test "returns sorted tasks as JSON" do
      conn =
        post_tasks([
          %{"name" => "task-1", "command" => "touch /tmp/file1"},
          %{"name" => "task-2", "command" => "cat /tmp/file1", "requires" => ["task-3"]},
          %{
            "name" => "task-3",
            "command" => "echo 'Hello World!' > /tmp/file1",
            "requires" => ["task-1"]
          },
          %{"name" => "task-4", "command" => "rm /tmp/file1", "requires" => ["task-2", "task-3"]}
        ])

      assert %{"tasks" => tasks} = json_response(conn, 200)
      names = Enum.map(tasks, & &1["name"])

      assert index(names, "task-1") < index(names, "task-3")
      assert index(names, "task-3") < index(names, "task-2")
      assert index(names, "task-2") < index(names, "task-4")
    end

    test "omits requires from the response, since the order encodes it" do
      conn = post_tasks([%{"name" => "a", "command" => "echo a", "requires" => []}])

      assert %{"tasks" => [task]} = json_response(conn, 200)
      assert task == %{"name" => "a", "command" => "echo a"}
    end

    test "sorts an empty task list to an empty list" do
      assert %{"tasks" => []} = json_response(post_tasks([]), 200)
    end

    test "returns sorted tasks as a bash script when Accept: text/plain" do
      conn =
        post_tasks(
          [
            %{"name" => "task-1", "command" => "touch /tmp/file1"},
            %{"name" => "task-2", "command" => "cat /tmp/file1", "requires" => ["task-1"]}
          ],
          "text/plain"
        )

      body = text_response(conn, 200)
      assert body =~ "#!/usr/bin/env bash"

      lines = String.split(body, "\n")
      assert Enum.find_index(lines, &(&1 =~ "touch")) < Enum.find_index(lines, &(&1 =~ "cat"))
    end

    test "returns 422 for circular dependency, naming a task in the cycle" do
      conn =
        post_tasks([
          %{"name" => "task-1", "command" => "echo a", "requires" => ["task-2"]},
          %{"name" => "task-2", "command" => "echo b", "requires" => ["task-1"]},
          %{"name" => "blocked", "command" => "echo c", "requires" => ["task-1"]}
        ])

      assert %{"error" => error} = json_response(conn, 422)
      assert error == "Tasks contain a circular dependency involving task-1"

      # `blocked` is walked first, but it is stuck behind the cycle, not in it.
      refute error =~ "blocked"
    end

    test "returns 422 for a missing dependency" do
      conn = post_tasks([%{"name" => "task-1", "command" => "echo a", "requires" => ["nope"]}])

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "non-existent task: nope"
    end

    test "returns 422 for duplicate task names rather than dropping a task" do
      conn =
        post_tasks([
          %{"name" => "dup", "command" => "echo first"},
          %{"name" => "dup", "command" => "echo second"}
        ])

      assert %{"error" => error} = json_response(conn, 422)
      assert error =~ "Duplicate task name: dup"
    end

    test "returns 400 with the offending index when requires is null" do
      conn =
        post_tasks([
          %{"name" => "ok", "command" => "echo a"},
          %{"name" => "bad", "command" => "echo b", "requires" => nil}
        ])

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Invalid task at index 1"
    end

    test "returns 400 when requires is not a list" do
      conn = post_tasks([%{"name" => "bad", "command" => "echo b", "requires" => "other"}])

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Invalid task at index 0"
    end

    test "returns 400 when requires contains a non-string" do
      conn = post_tasks([%{"name" => "bad", "command" => "echo b", "requires" => [1]}])

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Invalid task at index 0"
    end

    test "returns 400 for a task missing command" do
      conn = post_tasks([%{"name" => "bad"}])

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Invalid task at index 0"
    end

    test "returns 400 when the tasks key is missing" do
      conn = post_body(Jason.encode!(%{"nope" => []}))

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Expected"
    end

    test "returns 400 when tasks is not a list" do
      conn = post_body(Jason.encode!(%{"tasks" => "nope"}))

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "Expected"
    end

    test "returns 400 for a malformed JSON body" do
      conn = post_body(~s({"tasks": [}))

      assert %{"error" => error} = json_response(conn, 400)
      assert error =~ "not valid JSON"
    end

    test "preserves dependency order through the real parser" do
      body =
        Jason.encode!(%{
          "tasks" => [
            %{"name" => "second", "command" => "echo 2", "requires" => ["first"]},
            %{"name" => "first", "command" => "echo 1"}
          ]
        })

      assert %{"tasks" => tasks} = json_response(post_body(body), 200)
      assert Enum.map(tasks, & &1["name"]) == ["first", "second"]
    end
  end

  describe "input limits" do
    # Plug's 8 MB default is the only limit; the service sets none of its own.
    test "returns 413 when the request body exceeds Plug's default byte limit" do
      oversized =
        Jason.encode!(%{
          "tasks" => [%{"name" => "big", "command" => String.duplicate("x", 9_000_000)}]
        })

      conn = post_body(oversized)

      assert %{"error" => error} = json_response(conn, 413)
      assert error =~ "too large"
    end
  end

  describe "content negotiation" do
    test "defaults to JSON when no Accept header is sent" do
      conn = post_tasks([%{"name" => "a", "command" => "echo a"}], nil)

      assert %{"tasks" => [_]} = json_response(conn, 200)
    end

    test "treats */* as JSON" do
      conn = post_tasks([%{"name" => "a", "command" => "echo a"}], "*/*")

      assert %{"tasks" => [_]} = json_response(conn, 200)
    end

    test "ignores Accept parameters such as q" do
      conn = post_tasks([%{"name" => "a", "command" => "echo a"}], "text/plain; q=0.9")

      assert text_response(conn, 200) =~ "echo a"
    end

    test "respects client preference order" do
      tasks = [%{"name" => "a", "command" => "echo a"}]

      assert text_response(post_tasks(tasks, "text/plain, application/json"), 200) =~ "bash"

      assert %{"tasks" => _} =
               json_response(post_tasks(tasks, "application/json, text/plain"), 200)
    end

    test "skips unsupported types to reach a supported one" do
      conn = post_tasks([%{"name" => "a", "command" => "echo a"}], "application/xml, text/plain")

      assert text_response(conn, 200) =~ "echo a"
    end

    test "returns 406 for an unsupported Accept header" do
      conn = post_tasks([%{"name" => "t", "command" => "echo a"}], "application/xml")

      assert %{"error" => error} = json_response(conn, 406)
      assert error =~ "Accept"
    end
  end

  test "unknown route returns a JSON 404" do
    conn = :get |> conn("/unknown") |> call()

    assert %{"error" => _} = json_response(conn, 404)
  end

  test "an unsupported method on /tasks returns a JSON 404" do
    conn = :get |> conn("/tasks") |> call()

    assert %{"error" => _} = json_response(conn, 404)
  end

  defp index(list, element), do: Enum.find_index(list, &(&1 == element))
end
