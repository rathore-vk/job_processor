defmodule JobProcessor.Tasks.SorterTest do
  use ExUnit.Case, async: true

  alias JobProcessor.Tasks.Sorter
  alias JobProcessor.Tasks.Task

  doctest JobProcessor.Tasks.Sorter

  describe "sort/1" do
    test "empty list returns empty list" do
      assert {:ok, []} = sort_names([])
    end

    test "single task with no dependencies" do
      tasks = [%Task{name: "task-1", command: "echo hello"}]
      assert {:ok, ["task-1"]} = sort_names(tasks)
    end

    test "tasks with no dependencies are returned" do
      tasks = [
        %Task{name: "task-1", command: "echo a"},
        %Task{name: "task-2", command: "echo b"}
      ]

      assert {:ok, names} = sort_names(tasks)
      assert length(names) == 2
    end

    test "linear dependency chain is sorted correctly" do
      tasks = [
        %Task{name: "task-3", command: "echo c", requires: ["task-2"]},
        %Task{name: "task-1", command: "echo a"},
        %Task{name: "task-2", command: "echo b", requires: ["task-1"]}
      ]

      assert {:ok, ["task-1", "task-2", "task-3"]} = sort_names(tasks)
    end

    test "diamond dependency (example from prompt)" do
      tasks = [
        %Task{name: "task-1", command: "touch /tmp/file1"},
        %Task{name: "task-2", command: "cat /tmp/file1", requires: ["task-3"]},
        %Task{name: "task-3", command: "echo 'Hello World!' > /tmp/file1", requires: ["task-1"]},
        %Task{name: "task-4", command: "rm /tmp/file1", requires: ["task-2", "task-3"]}
      ]

      assert {:ok, names} = sort_names(tasks)

      assert index(names, "task-1") < index(names, "task-3")
      assert index(names, "task-3") < index(names, "task-2")
      assert index(names, "task-3") < index(names, "task-4")
      assert index(names, "task-2") < index(names, "task-4")
    end

    test "a dependency listed more than once is satisfied once" do
      tasks = [
        %Task{name: "task-2", command: "echo b", requires: ["task-1", "task-1"]},
        %Task{name: "task-1", command: "echo a"}
      ]

      assert {:ok, ["task-1", "task-2"]} = sort_names(tasks)
    end

    test "circular dependency comes back as the task the cycle closed on" do
      tasks = [
        %Task{name: "task-1", command: "echo a", requires: ["task-2"]},
        %Task{name: "task-2", command: "echo b", requires: ["task-1"]}
      ]

      assert {:cycle, "task-1"} = sort_names(tasks)
    end

    test "self-referencing task names itself" do
      tasks = [
        %Task{name: "task-1", command: "echo a", requires: ["task-1"]}
      ]

      assert {:cycle, "task-1"} = sort_names(tasks)
    end

    # `downstream` and `further` can't be sorted either, but they aren't the cause.
    test "a task stuck behind a cycle is not the one named" do
      tasks = [
        %Task{name: "a", command: "echo a", requires: ["b"]},
        %Task{name: "b", command: "echo b", requires: ["a"]},
        %Task{name: "downstream", command: "echo c", requires: ["a"]},
        %Task{name: "further", command: "echo d", requires: ["downstream"]}
      ]

      assert {:cycle, "a"} = sort_names(tasks)
    end

    # The walk stops at the first cycle, so only one is reported.
    test "two independent cycles name the one reached first" do
      tasks = [
        %Task{name: "y", command: "echo y", requires: ["z"]},
        %Task{name: "z", command: "echo z", requires: ["y"]},
        %Task{name: "a", command: "echo a", requires: ["b"]},
        %Task{name: "b", command: "echo b", requires: ["a"]}
      ]

      assert {:cycle, "a"} = sort_names(tasks)
    end

    test "the name it reports does not depend on input order" do
      tasks = [
        %Task{name: "y", command: "echo y", requires: ["z"]},
        %Task{name: "z", command: "echo z", requires: ["y"]},
        %Task{name: "a", command: "echo a", requires: ["b"]},
        %Task{name: "b", command: "echo b", requires: ["a"]}
      ]

      for permutation <- [tasks, Enum.reverse(tasks), Enum.shuffle(tasks)] do
        assert {:cycle, "a"} = sort_names(permutation)
      end
    end

    test "never drops or duplicates tasks in the output" do
      tasks =
        for i <- 1..25 do
          %Task{
            name: "task-#{i}",
            command: "echo #{i}",
            requires: if(i > 1, do: ["task-#{i - 1}"], else: [])
          }
        end

      assert {:ok, names} = sort_names(tasks)
      assert length(names) == 25
      assert names == Enum.map(tasks, & &1.name)
    end

    test "independent tasks are emitted in a deterministic order" do
      tasks = [
        %Task{name: "c", command: "echo c"},
        %Task{name: "a", command: "echo a"},
        %Task{name: "b", command: "echo b"}
      ]

      assert {:ok, ["a", "b", "c"]} = sort_names(tasks)
    end
  end

  # The tests above accept any valid order. These pin the exact one the service
  # promises.
  describe "the order it promises" do
    test "follows a chain to its end before starting the next root" do
      tasks = [
        %Task{name: "a", command: "echo a", requires: ["z"]},
        %Task{name: "b", command: "echo b"},
        %Task{name: "z", command: "echo z"}
      ]

      # `b` could go first, but the walk finishes `a`'s chain before starting it.
      assert {:ok, ["z", "a", "b"]} = sort_names(tasks)
    end

    test "returns the same order however the tasks arrive" do
      assert {:ok, baseline} = sort_names(graph())

      for permutation <- [Enum.reverse(graph()), Enum.shuffle(graph()), Enum.shuffle(graph())] do
        assert {:ok, ^baseline} = sort_names(permutation)
      end
    end

    # Over 32 names: smaller maps keep keys sorted, which would hide roots read unsorted from one.
    test "walks the roots in name order well past 32 of them" do
      tasks =
        for i <- 1..40 do
          %Task{name: "task-#{String.pad_leading("#{i}", 2, "0")}", command: "echo #{i}"}
        end

      names = Enum.map(tasks, & &1.name)

      assert {:ok, ^names} = sort_names(Enum.shuffle(tasks))
    end

    test "walks a task's dependencies in name order, not the order listed" do
      tasks = [
        %Task{name: "a", command: "echo a", requires: ["z", "b"]},
        %Task{name: "b", command: "echo b"},
        %Task{name: "z", command: "echo z"}
      ]

      assert {:ok, ["b", "z", "a"]} = sort_names(tasks)
    end

    defp graph do
      [
        %Task{name: "d", command: "echo d", requires: ["b", "c"]},
        %Task{name: "c", command: "echo c", requires: ["a"]},
        %Task{name: "b", command: "echo b", requires: ["a"]},
        %Task{name: "a", command: "echo a"},
        %Task{name: "loner", command: "echo loner"},
        %Task{name: "e", command: "echo e", requires: ["d", "loner"]}
      ]
    end
  end

  defp sort_names(tasks) do
    with {:ok, sorted} <- Sorter.sort(tasks), do: {:ok, Enum.map(sorted, & &1.name)}
  end

  defp index(list, element), do: Enum.find_index(list, &(&1 == element))
end
