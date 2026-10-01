defmodule JobProcessorWeb.ServerTest do
  # The only test over a real socket, so Bandit config errors fail here, not at boot.
  use ExUnit.Case, async: true

  @tasks [
    %{"name" => "task-2", "command" => "echo b", "requires" => ["task-1"]},
    %{"name" => "task-1", "command" => "echo a"}
  ]

  test "the supervised listener serves the router" do
    {head, body} = post_tasks(Jason.encode!(%{"tasks" => @tasks}))

    assert head =~ "HTTP/1.1 200 OK"
    assert head =~ "content-type: application/json"

    assert Jason.decode!(body) == %{
             "tasks" => [
               %{"name" => "task-1", "command" => "echo a"},
               %{"name" => "task-2", "command" => "echo b"}
             ]
           }
  end

  test "an unroutable path is still JSON" do
    {head, body} = get("/nope")

    assert head =~ "HTTP/1.1 404 Not Found"
    assert Jason.decode!(body) == %{"error" => "Not found"}
  end

  # Test config uses port 0, so ask Thousand Island which port it bound.
  defp port do
    assert [{_id, pid, _type, _modules}] = Supervisor.which_children(JobProcessor.Supervisor)
    assert {:ok, {_address, port}} = ThousandIsland.listener_info(pid)

    port
  end

  defp post_tasks(body) do
    request([
      "POST /tasks HTTP/1.1\r\n",
      "host: localhost\r\n",
      "accept: application/json\r\n",
      "content-type: application/json\r\n",
      "content-length: #{byte_size(body)}\r\n",
      "connection: close\r\n\r\n",
      body
    ])
  end

  defp get(path) do
    request([
      "GET #{path} HTTP/1.1\r\n",
      "host: localhost\r\n",
      "accept: application/json\r\n",
      "connection: close\r\n\r\n"
    ])
  end

  # `connection: close` lets us read to EOF instead of parsing content-length.
  defp request(lines) do
    {:ok, socket} = :gen_tcp.connect(~c"127.0.0.1", port(), [:binary, active: false], 1_000)
    :ok = :gen_tcp.send(socket, lines)

    response = read_until_closed(socket, "")
    :ok = :gen_tcp.close(socket)

    [head, rest] = String.split(response, "\r\n\r\n", parts: 2)
    {head, rest}
  end

  defp read_until_closed(socket, acc) do
    case :gen_tcp.recv(socket, 0, 1_000) do
      {:ok, chunk} -> read_until_closed(socket, acc <> chunk)
      {:error, :closed} -> acc
    end
  end
end
