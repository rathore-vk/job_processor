defmodule JobProcessor.Tasks.Sorter do
  @moduledoc """
  Depth-first topological sort.

  Each task's `requires` are walked first, then the task is pushed onto a stack.
  Reversing the stack gives an order where every task follows its dependencies.

  `adjacency` maps a task to what it *requires* — the reverse of the usual textbook
  graph, because the walk descends into dependencies.

  `visited` marks a task `:on_path` while its dependencies are being walked and
  `:finished` once it is pushed. Reaching a `:finished` task is a no-op; reaching an
  `:on_path` one is a cycle, and that task is the one reported.

  Roots and each task's `requires` are walked in name order, so the result depends
  only on the set of tasks, not the order they arrived in. A chain is followed to its
  end before the next root starts:

      iex> {:ok, sorted} = Sorter.sort([
      ...>   %Task{name: "a", command: "echo a", requires: ["z"]},
      ...>   %Task{name: "b", command: "echo b"},
      ...>   %Task{name: "z", command: "echo z"}
      ...> ])
      iex> Enum.map(sorted, & &1.name)
      ["z", "a", "b"]

  Recursion depth is the longest chain. The BEAM keeps the stack on the heap, so very
  deep chains are slow, not fatal.
  """

  alias JobProcessor.Tasks.Task

  require Logger

  @typedoc "A task the walk found inside a cycle."
  @type cycle :: String.t()

  @typep name :: String.t()
  @typep adjacency :: %{optional(name()) => [name()]}
  @typep visited :: %{optional(name()) => :on_path | :finished}
  @typep stack :: [name()]
  @typep outcome :: {:ok, visited(), stack()} | {:cycle, cycle()}

  @doc """
  Orders `tasks` so each one follows the tasks it requires.

  Expects input that has passed `JobProcessor.Tasks.Validation`, so the only possible
  failure is a cycle, returned as `{:cycle, name}`.
  """
  @spec sort([Task.t()]) :: {:ok, [Task.t()]} | {:cycle, cycle()}
  def sort([]), do: {:ok, []}

  def sort(tasks) when is_list(tasks) do
    task_names = tasks |> Enum.map(& &1.name) |> Enum.sort()
    adjacency = Map.new(tasks, fn %Task{} = task -> {task.name, Enum.sort(task.requires)} end)

    Logger.info("[Sorter] Sorting...", tasks: inspect(task_names))

    with {:ok, _visited, stack} <- visit_all(task_names, adjacency, %{}, []) do
      by_name = Map.new(tasks, &{&1.name, &1})

      {:ok, stack |> Enum.reverse() |> Enum.map(&Map.fetch!(by_name, &1))}
    end
  end

  # Used for both the roots and a task's `requires`. Stops at the first cycle.
  @spec visit_all([name()], adjacency(), visited(), stack()) :: outcome()
  defp visit_all([], _adjacency, visited, stack), do: {:ok, visited, stack}

  defp visit_all([name | rest], adjacency, visited, stack) do
    Logger.info("[Sorter] Visiting next",
      task: name,
      visited: inspect(visited),
      stack: inspect(stack)
    )

    with {:ok, visited, stack} <- visit(name, adjacency, visited, stack) do
      Logger.info("[Sorter] Visited", task: name, remaining: inspect(rest))

      visit_all(rest, adjacency, visited, stack)
    end
  end

  @spec visit(name(), adjacency(), visited(), stack()) :: outcome()
  defp visit(name, adjacency, visited, stack) do
    Logger.info("[Sorter] Checking", task: name, state: Map.get(visited, name, :unvisited))

    case Map.get(visited, name) do
      :finished -> {:ok, visited, stack}
      :on_path -> {:cycle, name}
      nil -> dfs(name, adjacency, Map.put(visited, name, :on_path), stack)
    end
  end

  # Push after the dependencies, so they are already on the stack.
  @spec dfs(name(), adjacency(), visited(), stack()) :: outcome()
  defp dfs(name, adjacency, visited, stack) do
    Logger.info("[Sorter] Descending", task: name, requires: inspect(Map.fetch!(adjacency, name)))

    with {:ok, visited, stack} <-
           visit_all(Map.fetch!(adjacency, name), adjacency, visited, stack) do
      {:ok, Map.put(visited, name, :finished), [name | stack]}
    end
  end
end
