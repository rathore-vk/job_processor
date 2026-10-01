defmodule JobProcessor.TasksTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Tasks
  alias JobProcessor.Tasks.Task

  describe "sort_tasks/1" do
    test "parses raw maps and returns structs in dependency order" do
      assert {:ok, sorted} =
               Tasks.sort_tasks([
                 %{"name" => "task-2", "command" => "echo b", "requires" => ["task-1"]},
                 %{"name" => "task-1", "command" => "echo a"}
               ])

      assert Enum.map(sorted, & &1.name) == ["task-1", "task-2"]
      assert Enum.all?(sorted, &match?(%Task{}, &1))
    end

    test "sorts an empty list" do
      assert {:ok, []} = Tasks.sort_tasks([])
    end

    test "names the index of a malformed task" do
      assert {:error, {:invalid_task, 1}} =
               Tasks.sort_tasks([
                 %{"name" => "task-1", "command" => "echo a"},
                 %{"name" => "task-2"}
               ])
    end

    # A malformed task is the more useful error than a cycle among invalid tasks.
    test "reports a malformed task ahead of a graph error" do
      assert {:error, {:invalid_task, 0}} =
               Tasks.sort_tasks([
                 %{"name" => "task-1"},
                 %{"name" => "task-2", "command" => "echo b", "requires" => ["task-2"]}
               ])
    end

    test "passes graph errors through from the sort" do
      assert {:error, {:circular_dependency, "a"}} =
               Tasks.sort_tasks([
                 %{"name" => "a", "command" => "echo a", "requires" => ["b"]},
                 %{"name" => "b", "command" => "echo b", "requires" => ["a"]}
               ])

      assert {:error, {:missing_dependency, "nope"}} =
               Tasks.sort_tasks([%{"name" => "a", "command" => "echo a", "requires" => ["nope"]}])

      assert {:error, {:duplicate_task, "a"}} =
               Tasks.sort_tasks([
                 %{"name" => "a", "command" => "echo a"},
                 %{"name" => "a", "command" => "echo b"}
               ])
    end
  end
end
