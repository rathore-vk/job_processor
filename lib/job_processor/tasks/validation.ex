defmodule JobProcessor.Tasks.Validation do
  @moduledoc """
  Checks that task names are unique and every `requires` entry names a real task.

  Runs before `JobProcessor.Tasks.Sorter`, which then only has to detect cycles.
  """

  alias JobProcessor.Tasks.Task

  @type error ::
          {:duplicate_task, String.t()}
          | {:missing_dependency, String.t()}

  @doc """
  Returns `:ok`, or the first problem found.

  ## Examples

      iex> Validation.validate([
      ...>   %Task{name: "a", command: "echo a"},
      ...>   %Task{name: "b", command: "echo b", requires: ["a"]}
      ...> ])
      :ok

      iex> Validation.validate([
      ...>   %Task{name: "a", command: "echo first"},
      ...>   %Task{name: "a", command: "echo second"}
      ...> ])
      {:error, {:duplicate_task, "a"}}

      iex> Validation.validate([%Task{name: "a", command: "echo a", requires: ["ghost"]}])
      {:error, {:missing_dependency, "ghost"}}

  """
  @spec validate([Task.t()]) :: :ok | {:error, error()}
  def validate(tasks) when is_list(tasks) do
    names = MapSet.new(tasks, & &1.name)

    with :ok <- validate_unique_names(tasks, names) do
      validate_dependencies(tasks, names)
    end
  end

  # Without this, duplicates would collapse into one task and silently go missing.
  defp validate_unique_names(tasks, names) do
    if length(tasks) == MapSet.size(names) do
      :ok
    else
      {:error, {:duplicate_task, first_duplicate(tasks)}}
    end
  end

  defp first_duplicate(tasks) do
    Enum.reduce_while(tasks, MapSet.new(), fn %Task{name: name}, seen ->
      if MapSet.member?(seen, name),
        do: {:halt, name},
        else: {:cont, MapSet.put(seen, name)}
    end)
  end

  defp validate_dependencies(tasks, known) do
    tasks
    |> Enum.flat_map(fn %Task{requires: requires} -> requires end)
    |> Enum.find(fn dep -> not MapSet.member?(known, dep) end)
    |> case do
      nil -> :ok
      missing -> {:error, {:missing_dependency, missing}}
    end
  end
end
