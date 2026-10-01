defmodule JobProcessor.Tasks.TaskTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Tasks.Task

  doctest JobProcessor.Tasks.Task

  describe "new/1" do
    test "builds a task and defaults requires to an empty list" do
      assert {:ok, task} = Task.new(%{"name" => "t", "command" => "echo a"})
      assert task.name == "t"
      assert task.command == "echo a"
      assert task.requires == []
    end

    test "accepts a list of string dependencies" do
      assert {:ok, task} =
               Task.new(%{"name" => "t", "command" => "echo a", "requires" => ["a", "b"]})

      assert task.requires == ["a", "b"]
    end

    test "rejects a missing name or command" do
      assert {:error, :invalid_task} = Task.new(%{"command" => "echo a"})
      assert {:error, :invalid_task} = Task.new(%{"name" => "t"})
      assert {:error, :invalid_task} = Task.new(%{})
      assert {:error, :invalid_task} = Task.new("not-a-map")
    end

    test "rejects a non-string name or command" do
      assert {:error, :invalid_task} = Task.new(%{"name" => 1, "command" => "echo a"})
      assert {:error, :invalid_task} = Task.new(%{"name" => "t", "command" => 1})
    end

    # `Map.get/3` only defaults when the key is absent, not when it is null.
    test "rejects an explicit null requires" do
      assert {:error, :invalid_task} =
               Task.new(%{"name" => "t", "command" => "echo a", "requires" => nil})
    end

    test "rejects a requires that is not a list of strings" do
      assert {:error, :invalid_task} =
               Task.new(%{"name" => "t", "command" => "echo a", "requires" => "a"})

      assert {:error, :invalid_task} =
               Task.new(%{"name" => "t", "command" => "echo a", "requires" => [1]})

      assert {:error, :invalid_task} =
               Task.new(%{"name" => "t", "command" => "echo a", "requires" => %{"a" => 1}})
    end
  end

  describe "parse_many/1" do
    test "parses a list of tasks in order" do
      assert {:ok, [a, b]} =
               Task.parse_many([
                 %{"name" => "a", "command" => "echo a"},
                 %{"name" => "b", "command" => "echo b"}
               ])

      assert a.name == "a"
      assert b.name == "b"
    end

    test "returns an empty list for no tasks" do
      assert {:ok, []} = Task.parse_many([])
    end

    test "reports the index of the first invalid task" do
      assert {:error, {:invalid_task, 0}} = Task.parse_many([%{"name" => "a"}])

      assert {:error, {:invalid_task, 2}} =
               Task.parse_many([
                 %{"name" => "a", "command" => "echo a"},
                 %{"name" => "b", "command" => "echo b"},
                 %{"name" => "c", "command" => "echo c", "requires" => nil}
               ])
    end
  end
end
