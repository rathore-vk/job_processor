defmodule JobProcessor.Tasks.Task do
  @moduledoc """
  A single task: a unique `name`, a shell `command`, and the names of the tasks it
  `requires` to run first.
  """

  @enforce_keys [:name, :command]
  defstruct [:name, :command, requires: []]

  @type t :: %__MODULE__{
          name: String.t(),
          command: String.t(),
          requires: [String.t()]
        }

  @doc """
  Builds a `%Task{}` from a decoded JSON map.

  `requires` is optional, but if present must be a list of strings.

  ## Examples

      iex> Task.new(%{"name" => "build", "command" => "make"})
      {:ok, %Task{name: "build", command: "make", requires: []}}

      iex> Task.new(%{"name" => "test", "command" => "mix test", "requires" => ["build"]})
      {:ok, %Task{name: "test", command: "mix test", requires: ["build"]}}

  An explicit `null` is rejected, not defaulted to `[]`:

      iex> Task.new(%{"name" => "a", "command" => "echo a", "requires" => nil})
      {:error, :invalid_task}

      iex> Task.new(%{"name" => "a"})
      {:error, :invalid_task}

  """
  @spec new(map()) :: {:ok, t()} | {:error, :invalid_task}
  def new(%{"name" => name, "command" => command} = attrs)
      when is_binary(name) and is_binary(command) do
    requires = Map.get(attrs, "requires", [])

    if valid_requires?(requires) do
      {:ok, %__MODULE__{name: name, command: command, requires: requires}}
    else
      {:error, :invalid_task}
    end
  end

  def new(_), do: {:error, :invalid_task}

  @doc """
  Parses a list of raw maps, stopping at the first invalid one and returning its
  index.

  ## Examples

      iex> Task.parse_many([%{"name" => "a", "command" => "echo a"}])
      {:ok, [%Task{name: "a", command: "echo a", requires: []}]}

      iex> Task.parse_many([
      ...>   %{"name" => "a", "command" => "echo a"},
      ...>   %{"name" => "b", "requires" => ["a"]}
      ...> ])
      {:error, {:invalid_task, 1}}

  """
  @spec parse_many([map()]) :: {:ok, [t()]} | {:error, {:invalid_task, non_neg_integer()}}
  def parse_many(raw_tasks) when is_list(raw_tasks) do
    raw_tasks
    |> Enum.with_index()
    |> Enum.reduce_while([], fn {raw, index}, acc ->
      case new(raw) do
        {:ok, task} -> {:cont, [task | acc]}
        {:error, :invalid_task} -> {:halt, {:error, {:invalid_task, index}}}
      end
    end)
    |> case do
      {:error, _} = error -> error
      tasks -> {:ok, Enum.reverse(tasks)}
    end
  end

  defp valid_requires?(requires) when is_list(requires), do: Enum.all?(requires, &is_binary/1)
  defp valid_requires?(_), do: false
end
