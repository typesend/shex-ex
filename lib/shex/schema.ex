defmodule ShEx.Schema do
  @moduledoc """
  A ShEx schema is a collection of ShEx shape expressions that prescribes conditions that RDF data graphs must meet in order to be considered "conformant".

  Usually a `ShEx.Schema` is not created by hand, but read from a ShExC or ShExJ
  representation via `ShEx.ShExC.decode/2` or `ShEx.ShExJ.decode/2`.
  """

  defstruct [
    :shapes,     # [shapeExpr+]?
    :start,      # shapeExpr?
    :imports,    # [IRI+]?
    :start_acts  # [SemAct+]?
  ]

  alias ShEx.{ShapeMap, ShapeExpression}

  @parallel_default Application.get_env(:shex, :parallel, false)
  @flow_opts_defaults Application.get_env(:shex, :flow_opts)
  @flow_opts MapSet.new(~w[max_demand min_demand stages window buffer_keep buffer_size]a)

  @doc !"""
  Creates a `ShEx.Schema`.
  """
  def new(shapes, start \\ nil, imports \\ nil, start_acts \\ nil) do
    %ShEx.Schema{
      shapes: shapes |> List.wrap() |> Map.new(fn shape -> {shape.id, shape} end),
      start: start,
      imports: imports,
      start_acts: start_acts
    }
  end

  @doc """
  Validates that a `RDF.Data` structure conforms to a `ShEx.Schema` according to a `ShEx.ShapeMap`.
  """
  def validate(schema, data, shape_map, opts \\ [])

  def validate(schema, data, %ShapeMap{type: :query} = shape_map, opts) do
    with {:ok, fixed_shape_map} <- ShapeMap.to_fixed(shape_map, data) do
      validate(schema, data, fixed_shape_map, opts)
    end
  end

  def validate(schema, data, %ShapeMap{type: :fixed} = shape_map, opts) do
    start = start_shape_expr(schema)
    state = %{
      ref_stack: [],
      labeled_triple_expressions:
        schema.shapes |> Map.values() |> labeled_triple_expressions()
    }

    if par_opts = parallelization_options(shape_map, data, opts) do
      shape_map
      |> ShapeMap.associations()
      |> Flow.from_enumerable(par_opts)
      |> Flow.map(fn association ->
           if shape = shape_expr(schema, association.shape, start) do
             ShapeExpression.satisfies(shape, data, schema, association, state)
           else
             ShapeMap.Association.violation(association,
               %ShEx.Violation.UnknownReference{expr_ref: association.shape})
           end
      end)
      |> Enum.reduce(%ShapeMap{type: :result}, fn association, shape_map ->
           ShapeMap.add(shape_map, association)
         end)
    else
      shape_map
      |> ShapeMap.associations()
      |> Enum.reduce(%ShapeMap{type: :result}, fn association, result_shape_map ->
           if shape = shape_expr(schema, association.shape, start) do
             ShapeMap.add(result_shape_map,
               ShapeExpression.satisfies(shape, data, schema, association, state)
             )
           else
             ShapeMap.add(result_shape_map,
               ShapeMap.Association.violation(association,
                 %ShEx.Violation.UnknownReference{expr_ref: association.shape})
             )
           end
         end)
    end
  end

  defp parallelization_options(shape_map, data, opts) do
    if Keyword.get(opts, :parallel, @parallel_default) do
      if opts |> Keyword.keys() |> MapSet.new() |> MapSet.disjoint?(@flow_opts) do
        flow_opts_defaults(shape_map, data, opts)
      else
        opts
      end
    end
  end

  defp flow_opts_defaults(shape_map, data, opts) do
    @flow_opts_defaults || [] # TODO: provide sensible defaults based on the input
  end

  defp labeled_triple_expressions(operators) do
    Enum.reduce(operators, %{}, fn operator, acc ->
      case ShEx.Operator.triple_expression_label_and_operands(operator) do
        {nil, []} ->
          acc

        {triple_expr_label, []} ->
          acc
          |> Map.put(triple_expr_label, operator)

        {nil, triple_expressions} ->
          acc
          |> Map.merge(labeled_triple_expressions(triple_expressions))

        {triple_expr_label, triple_expressions} ->
          acc
          |> Map.put(triple_expr_label, operator)
          |> Map.merge(labeled_triple_expressions(triple_expressions))
      end
    end)
  end

  @doc false
  def shape_expr_with_id(schema, shape_label) do
    Map.get(schema.shapes, shape_label)
  end

  defp start_shape_expr(schema) do
    if RDF.resource?(schema.start) do
      shape_expr_with_id(schema, schema.start)
    else
      schema.start
    end
  end

  defp shape_expr(_, :start, start_expr), do: start_expr
  defp shape_expr(schema, shape_label, _), do: shape_expr_with_id(schema, shape_label)
end
