defmodule JobProcessor.Tasks do
  @moduledoc """
  The task context — the only module the web layer calls.

  A job is a list of tasks, each with a `name`, a shell `command` and an optional
  list of tasks it `requires`. This module returns them in a valid execution order,
  or says why there isn't one. It never runs the commands.
  """

  alias JobProcessor.Tasks.Sorter
  alias JobProcessor.Tasks.Task
  alias JobProcessor.Tasks.Validation

  require Logger

  @typedoc "Every way a list of raw tasks can fail to produce an order."
  @type error ::
          {:invalid_task, non_neg_integer()}
          | Validation.error()
          | {:circular_dependency, Sorter.cycle()}

  @doc """
  Parses, validates and sorts raw task maps.

  Errors:

    * `{:invalid_task, index}` — a task is malformed
    * `{:duplicate_task, name}` — two tasks share a name
    * `{:missing_dependency, name}` — a task requires an unknown task
    * `{:circular_dependency, name}` — `name` is part of a cycle
  """
  @spec sort_tasks([map()]) :: {:ok, [Task.t()]} | {:error, error()}
  def sort_tasks(tasks) do
    Logger.info("[Tasks] Sorting tasks", tasks: inspect(tasks))

    with {:ok, parsed_tasks} <- Task.parse_many(tasks),
         :ok <- Validation.validate(parsed_tasks),
         {:ok, sorted_tasks} <- Sorter.sort(parsed_tasks) do
      Logger.info("[Tasks] Sorted tasks", order: inspect(Enum.map(sorted_tasks, & &1.name)))

      {:ok, sorted_tasks}
    else
      {:cycle, name} -> {:error, {:circular_dependency, name}}
      {:error, reason} -> {:error, reason}
    end
  end
end
