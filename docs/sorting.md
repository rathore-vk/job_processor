# Sorting

`JobProcessor.Tasks.Sorter` is a depth-first walk. It visits everything a task requires, then pushes
the task onto a stack. Reversing the stack gives an order where each task follows its dependencies.

If the walk reaches a task it's still inside, that's a cycle, and that task is reported. See
[Errors](errors.md).

Input has already passed `Validation`, so the walk never sees duplicate names or unknown
dependencies.

Two alternatives were tried and removed:

- **Kahn's algorithm** got slower as graphs got wider, because each step scanned the ready set for
  the smallest name.
- **`:digraph_utils.topsort/1`** was slower on most shapes, because the graph has to be loaded into
  ETS tables first.

## Determinism

A depth-first sort can start from any root and visit dependencies in any order. Left alone, that
would follow input or map order. So both are sorted: roots and each task's `requires` are visited in
name order. The result depends only on the set of tasks, which is what makes
`sort(tasks) == sort(Enum.reverse(tasks))` testable.

It is not "smallest available name first". A chain is finished before the next root starts:

```
a requires z, plus an independent b   →   z, a, b
```

`b` could have gone first. This is the order the service promises, and `SorterTest` pins it.

### Sorting has to be explicit

Erlang maps keep their keys sorted up to 32 entries and stop above that:

```
n= 32  sorted? true
n= 33  sorted? false
```

So code that relies on map order passes small tests and breaks on real input. That's why the roots
and `requires` are sorted explicitly, and why one test uses 40 tasks.

## Cost

O(V + E): each task is walked once, and each `requires` entry is checked once. Best of three, with
validation included:

| Shape | Time |
|---|---|
| 5,000 independent tasks | 3.8 ms |
| 10,000 independent tasks | 7.9 ms |
| 20,000 independent tasks | 17.2 ms |
| 250,000 independent tasks | 319.3 ms |
| 1 task unblocking 10,000 | 7.1 ms |
| 50,000-task chain | 49.4 ms |

Time roughly doubles with size, and graph shape barely matters.

Recursion depth equals the longest chain. The BEAM keeps the stack on the heap, so a 50,000-task chain
is slow to build but doesn't overflow.

## Scaling

The service is stateless, so add nodes behind a load balancer. Memory × concurrency is the real
limit, not CPU; see [Limits](api.md#limits).

The most useful next step would be **mapping task names to integers**. Each `requires` entry is a
separate copy of the name, so integer keys would cut memory several times over and speed up every
comparison.
