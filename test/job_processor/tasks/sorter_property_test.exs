defmodule JobProcessor.Tasks.SorterPropertyTest do
  @moduledoc """
  Invariants of `Sorter.sort/1` that must hold for every generated input.
  """

  use ExUnit.Case, async: true
  use ExUnitProperties

  alias JobProcessor.Tasks
  alias JobProcessor.Tasks.Sorter
  alias JobProcessor.Tasks.Task

  @absent "__no_such_task__"

  describe "invariants over arbitrary DAGs" do
    property "output is a permutation of the input — nothing dropped or duplicated" do
      check all(tasks <- dag()) do
        assert {:ok, sorted} = Sorter.sort(tasks)
        assert length(sorted) == length(tasks)
        assert Enum.sort(names(sorted)) == Enum.sort(names(tasks))
      end
    end

    property "every task appears after all of the tasks it requires" do
      check all(tasks <- dag()) do
        assert {:ok, sorted} = Sorter.sort(tasks)

        position = sorted |> names() |> Enum.with_index() |> Map.new()

        for task <- tasks, dep <- task.requires do
          assert position[dep] < position[task.name],
                 "#{task.name} requires #{dep} but was placed before it"
        end
      end
    end

    property "any valid DAG sorts successfully" do
      check all(tasks <- dag()) do
        assert {:ok, _} = Sorter.sort(tasks)
      end
    end

    # Reverses each task's `requires` too, since the walk depends on both orders.
    property "result does not depend on input order" do
      check all(tasks <- dag()) do
        assert {:ok, forward} = Sorter.sort(tasks)

        reversed =
          tasks
          |> Enum.reverse()
          |> Enum.map(fn %Task{} = task ->
            %Task{task | requires: Enum.reverse(task.requires)}
          end)

        # By name, because the reversed `requires` make the structs differ.
        assert {:ok, backward} = Sorter.sort(reversed)
        assert names(backward) == names(forward)
      end
    end

    property "sorting is idempotent — sorting the output again changes nothing" do
      check all(tasks <- dag()) do
        assert {:ok, once} = Sorter.sort(tasks)

        assert {:ok, ^once} = Sorter.sort(once)
      end
    end
  end

  describe "invariants over invalid input" do
    # Through `Tasks`, since these errors come from validation as well as the sort.
    property "a cycle of any length is rejected" do
      check all(n <- integer(2..15)) do
        # t1 <- t2 <- ... <- tn, closed by t1 requiring tn.
        chain =
          for i <- 1..n do
            requires = if i == 1, do: ["t#{n}"], else: ["t#{i - 1}"]
            %Task{name: "t#{i}", command: "echo #{i}", requires: requires}
          end

        # Every task is in the cycle, so any of them is a valid answer.
        assert {:error, {:circular_dependency, name}} = sort_tasks(chain)
        assert name in names(chain)
      end
    end

    property "a reference to an unknown task is reported by name" do
      check all(tasks <- dag()) do
        dangling = %Task{name: "dangling", command: "echo x", requires: [@absent]}

        assert {:error, {:missing_dependency, @absent}} =
                 sort_tasks(tasks ++ [dangling])
      end
    end

    property "a repeated name is rejected rather than silently collapsing" do
      check all(tasks <- dag(), duplicate <- member_of(names(tasks))) do
        clashing = %Task{name: duplicate, command: "echo clash"}

        assert {:error, {:duplicate_task, ^duplicate}} =
                 sort_tasks(tasks ++ [clashing])
      end
    end
  end

  defp sort_tasks(tasks) do
    Tasks.sort_tasks(
      Enum.map(tasks, fn %Task{} = task ->
        %{"name" => task.name, "command" => task.command, "requires" => task.requires}
      end)
    )
  end

  # Acyclic by construction: task `i` only requires lower-indexed tasks.
  defp dag(max_nodes \\ 12) do
    gen all(
          n <- integer(1..max_nodes),
          edges <- edges_for(n)
        ) do
      [1..n, edges]
      |> Enum.zip()
      |> Enum.map(fn {i, requires} ->
        %Task{
          name: "t#{i}",
          command: "echo #{i}",
          requires: Enum.map(requires, &"t#{&1}")
        }
      end)
    end
  end

  # Picks each candidate in or out (2:1 against, for sparse graphs), so entries are
  # unique without `uniq_list_of/2`, which can fail to find enough distinct values.
  defp edges_for(n) do
    1..n
    |> Enum.map(fn
      1 ->
        constant([])

      i ->
        1..(i - 1)
        |> Enum.map(fn j -> frequency([{2, constant(nil)}, {1, constant(j)}]) end)
        |> fixed_list()
        |> StreamData.map(&Enum.reject(&1, fn dep -> is_nil(dep) end))
    end)
    |> fixed_list()
  end

  defp names(tasks), do: Enum.map(tasks, & &1.name)
end
