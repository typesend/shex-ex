defmodule ShEx.ShapeMapTest do
  use ExUnit.Case
  doctest ShEx.ShapeMap

  import RDF.Sigils

  alias ShEx.ShapeMap

  use RDF.Vocabulary.Namespace

  defvocab EX,
           base_iri: "http://example.org/#",
           terms: [], strict: false


  @iri ~I<http://example.org/#foo>
  @bnode ~B<foo>
  @literal ~L"foo"
  @shape_label ~I<http://example.org/#Shape>

  @conformant_association ShapeMap.Association.new(@iri, @shape_label)
  @nonconformant_association ShapeMap.Association.new(@literal, @shape_label)
                             |> ShapeMap.Association.violation("error")
  @conformant_fixed_shape_map ShapeMap.new([@conformant_association])
  @nonconformant_fixed_shape_map ShapeMap.new([@conformant_association, @nonconformant_association])

  describe "new/1" do
    test "when given a map of node-shape identifier pairs" do
      assert ShapeMap.new(%{@iri => @shape_label}) ==
               %ShapeMap{type: :fixed, conformant: [%ShapeMap.Association{node: @iri, shape: @shape_label}]}
      assert ShapeMap.new(%{@bnode => @shape_label}) ==
               %ShapeMap{type: :fixed, conformant: [%ShapeMap.Association{node: @bnode, shape: @shape_label}]}
      assert ShapeMap.new(%{@literal => @shape_label}) ==
               %ShapeMap{type: :fixed, conformant: [%ShapeMap.Association{node: @literal, shape: @shape_label}]}

      assert ShapeMap.new(%{
               @iri => @shape_label,
               @bnode => @shape_label,
               @literal => @shape_label
             }) == %ShapeMap{type: :fixed, conformant: [
               %ShapeMap.Association{node: @literal, shape: @shape_label},
               %ShapeMap.Association{node: @iri, shape: @shape_label},
               %ShapeMap.Association{node: @bnode, shape: @shape_label},
             ]}
    end

    test "when given a map of node-shape identifier pairs consisting of vocabulary atoms" do
      assert ShapeMap.new(%{EX.Foo => EX.Shape}) ==
               %ShapeMap{
                 type: :fixed,
                 conformant: [%ShapeMap.Association{node: ~I<http://example.org/#Foo>, shape: @shape_label}]
               }
    end

    test "when given a map with triple patterns" do
      assert ShapeMap.new(%{{:focus, @iri, @bnode} => @shape_label}) ==
               %ShapeMap{
                 type: :query,
                 conformant: [
                   %ShapeMap.Association{
                     node: {:focus, @iri, @bnode},
                     shape: @shape_label
                   }
                 ]
               }
    end

    test "when given a map with triple patterns consisting of vocabulary atoms" do
      assert ShapeMap.new(%{{EX.Bar, EX.foo, :focus} => EX.Shape}) ==
               %ShapeMap{
                 type: :query,
                 conformant: [
                   %ShapeMap.Association{
                     node: {~I<http://example.org/#Bar>, @iri, :focus},
                     shape: @shape_label
                   }
                 ]
               }

      assert ShapeMap.new(%{{:focus, EX.Foo, :_} => EX.Shape}) ==
               %ShapeMap{
                 type: :query,
                 conformant: [
                   %ShapeMap.Association{
                     node: {:focus, ~I<http://example.org/#Foo>, :_},
                     shape: @shape_label
                   }
                 ]
               }
    end
  end

  describe "fixed?/1" do
    test "returns true when given a fixed ShapeMap" do
      assert ShapeMap.fixed?(%ShapeMap{type: :fixed}) == true
    end

    test "returns false when given a query ShapeMap" do
      assert ShapeMap.fixed?(%ShapeMap{type: :query}) == false
    end

    test "returns false when given a result ShapeMap" do
      assert ShapeMap.fixed?(%ShapeMap{type: :result}) == false
    end

    test "returns nil when given a ShapeMap with an unknown type" do
      assert ShapeMap.fixed?(%ShapeMap{type: :foo}) == nil
      assert ShapeMap.fixed?(%ShapeMap{type: nil}) == nil
    end
  end

  describe "query?/1" do
    test "returns true when given a fixed ShapeMap" do
      assert ShapeMap.query?(%ShapeMap{type: :fixed}) == true
    end

    test "returns true when given a query ShapeMap" do
      assert ShapeMap.query?(%ShapeMap{type: :query}) == true
    end

    test "returns true when given a result ShapeMap" do
      assert ShapeMap.query?(%ShapeMap{type: :result}) == false
    end

    test "returns nil when given a ShapeMap with an unknown type" do
      assert ShapeMap.query?(%ShapeMap{type: :foo}) == nil
      assert ShapeMap.query?(%ShapeMap{type: nil}) == nil
    end
  end

  describe "result?/1" do
    test "returns false when given a fixed ShapeMap" do
      assert ShapeMap.result?(%ShapeMap{type: :fixed}) == false
    end

    test "returns false when given a query ShapeMap" do
      assert ShapeMap.result?(%ShapeMap{type: :query}) == false
    end

    test "returns true when given a result ShapeMap" do
      assert ShapeMap.result?(%ShapeMap{type: :result}) == true
    end

    test "returns nil when given a ShapeMap with an unknown type" do
      assert ShapeMap.result?(%ShapeMap{type: :foo}) == nil
      assert ShapeMap.result?(%ShapeMap{type: nil}) == nil
    end
  end

  describe "to_fixed/1" do
    # TODO:
  end

  describe "Enumerable protocol" do
    test "Enum.count" do
      assert Enum.count(ShapeMap.new) == 0
      assert Enum.count(@conformant_fixed_shape_map) == 1
      assert Enum.count(@nonconformant_fixed_shape_map) == 2
    end

    test "Enum.member?" do
      assert Enum.member?(@nonconformant_fixed_shape_map, @conformant_association)
      assert Enum.member?(@nonconformant_fixed_shape_map, @nonconformant_association)
      refute Enum.member?(@conformant_fixed_shape_map, @nonconformant_association)
    end

    test "Enum.reduce" do
      assert Enum.reduce(@nonconformant_fixed_shape_map, [], fn (association, acc) ->
               [association | acc]
             end) == [@nonconformant_association, @conformant_association]
    end
  end
end
