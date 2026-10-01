defmodule JobProcessor.Tasks.ValidationTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Tasks.Task
  alias JobProcessor.Tasks.Validation

  doctest JobProcessor.Tasks.Validation

  describe "validate/1" do
    test "a valid graph passes" do
      tasks = [
        %Task{name: "b", command: "echo b", requires: ["a"]},
        %Task{name: "a", command: "echo a"}
      ]

      assert :ok = Validation.validate(tasks)
    end

    test "an empty list is valid" do
      assert :ok = Validation.validate([])
    end

    test "reports the first duplicate name in input order" do
      tasks = [
        %Task{name: "a", command: "echo a"},
        %Task{name: "b", command: "echo b"},
        %Task{name: "b", command: "echo again"},
        %Task{name: "a", command: "echo again"}
      ]

      assert {:error, {:duplicate_task, "b"}} = Validation.validate(tasks)
    end

    test "reports a dependency that names no task" do
      tasks = [
        %Task{name: "a", command: "echo a"},
        %Task{name: "b", command: "echo b", requires: ["a", "ghost"]}
      ]

      assert {:error, {:missing_dependency, "ghost"}} = Validation.validate(tasks)
    end

    test "a task requiring itself is left for the sorter to reject as a cycle" do
      tasks = [%Task{name: "a", command: "echo a", requires: ["a"]}]

      assert :ok = Validation.validate(tasks)
    end

    test "duplicates are reported before missing dependencies" do
      tasks = [
        %Task{name: "a", command: "echo a", requires: ["ghost"]},
        %Task{name: "a", command: "echo again"}
      ]

      assert {:error, {:duplicate_task, "a"}} = Validation.validate(tasks)
    end
  end
end
