defmodule Pix.Pipeline.Graph do
  @moduledoc false

  @type edge() :: {from_node :: gnode(), to_node :: gnode()}
  @type gnode() :: String.t()
  @type t() :: [edge() | gnode()]

  @spec get(Pix.Pipeline.SDK.t()) :: t()
  def get(%Pix.Pipeline.SDK{} = pipeline) do
    stage_nodes = for stage <- pipeline.stages, do: stage.stage

    stage_deps_edges =
      for stage <- pipeline.stages, instruction <- stage.instructions, uniq: true do
        case instruction do
          {"FROM", _from_opts, [from_arg]} ->
            [depends_from | _] = from_arg |> String.split(" ")
            {depends_from, stage.stage}

          {"COPY", copy_opts, _copy_args} ->
            pipeline_ctx = Pix.Pipeline.SDK.pipeline_ctx()

            case copy_opts[:from] do
              nil -> nil
              ^pipeline_ctx -> nil
              depends_from -> {depends_from, stage.stage}
            end

          _ ->
            nil
        end
      end

    stage_deps_edges = Enum.reject(stage_deps_edges, &is_nil/1)

    stage_nodes ++ stage_deps_edges
  end

  @spec roots(t()) :: [gnode()]
  def roots(dag) do
    all_nodes = nodes(dag)
    child_nodes = MapSet.new(Enum.map(edges(dag), &elem(&1, 1)))
    MapSet.difference(all_nodes, child_nodes) |> MapSet.to_list()
  end

  @spec roots(t()) :: [gnode()]
  def nodes(dag), do: MapSet.new(Enum.flat_map(edges(dag), &Tuple.to_list/1) ++ single_nodes(dag))

  @spec edges(t()) :: [edge()]
  def edges(dag), do: dag |> Enum.split_with(&is_tuple/1) |> elem(0)

  @spec single_nodes(t()) :: [gnode()]
  def single_nodes(dag), do: dag |> Enum.split_with(&is_tuple/1) |> elem(1)

  @spec adjacency_list(t()) :: %{gnode() => [child :: gnode()]}
  def adjacency_list(dag), do: dag |> edges() |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
end
