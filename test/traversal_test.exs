defmodule SourcerorTest.TraversalTest do
  use ExUnit.Case, async: true
  doctest Sourceror.Traversal

  # @moduletag :skip

  import Sourceror, only: [parse_string!: 1]

  import Sourceror.Traversal, only: [traverse: 4]

  describe "traverse/4" do
    test "propagates line corrections for unqualified calls" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a(b)"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:a, a_meta, [{:b, b_meta, _}]} = ast
      assert a_meta[:line] == 1
      assert b_meta[:line] == 2

      {ast, _} =
        traverse(parse_string!("a(b, c)"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: 1}}

          {:b, meta, context}, state ->
            {{:b, meta, context}, %{state | line_correction: 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:a, a_meta, [{:b, b_meta, _}, {:c, c_meta, _}]} = ast
      assert a_meta[:line] == 1
      assert b_meta[:line] == 2
      assert c_meta[:line] == 3
    end

    test "propagates line corrections for unqualified calls with do block" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a(b) do c end"), nil, noop, fn
          {:a, meta, args}, state ->
            {{:a, meta, args}, %{state | line_correction: state.line_correction + 1}}

          {:b, meta, context}, state ->
            {{:b, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:c, meta, context}, state ->
            {{:c, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:a, a_meta,
              [
                {:b, b_meta, _},
                [{{:__block__, do_meta, [:do]}, {:c, c_meta, _}}]
              ]} = ast

      assert a_meta[:line] == 1
      assert b_meta[:line] == 2
      assert a_meta[:closing][:line] == 3
      assert a_meta[:do][:line] == 3
      assert do_meta[:line] == 3
      assert c_meta[:line] == 3
      assert a_meta[:end][:line] == 4
    end

    test "propagates line corrections for qualified calls" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a.b"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta, [{:a, a_meta, _}, :b]}, b_meta, []} = ast
      assert a_meta[:line] == 1
      assert dot_meta[:line] == 2
      assert b_meta[:line] == 2

      {ast, _} =
        traverse(parse_string!("a.b(c)"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          :b, state ->
            {:b, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta, [{:a, a_meta, _}, :b]}, b_meta, [{:c, c_meta, _}]} = ast

      assert a_meta[:line] == 1
      assert dot_meta[:line] == 2
      assert b_meta[:line] == 2
      assert c_meta[:line] == 3
      assert b_meta[:closing][:line] == 3
    end

    test "propagates line corrections to next siblings" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a.b(c, d, e)"), nil, noop, fn
          {:c, meta, context}, state ->
            {{:c, meta, context}, %{state | line_correction: 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta, [{:a, a_meta, _}, :b]}, b_meta,
              [
                {:c, c_meta, _},
                {:d, d_meta, _},
                {:e, e_meta, _}
              ]} = ast

      assert dot_meta[:line] == 1
      assert a_meta[:line] == 1
      assert b_meta[:line] == 1
      assert c_meta[:line] == 1
      assert d_meta[:line] == 2
      assert e_meta[:line] == 2
    end

    test "propagates line corrections to closing fields" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a.b(c)"), nil, noop, fn
          {:c, meta, context}, state ->
            {{:c, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta, [{:a, a_meta, _}, :b]}, b_meta, [{:c, c_meta, _}]} = ast

      assert a_meta[:line] == 1
      assert dot_meta[:line] == 1
      assert b_meta[:line] == 1
      assert c_meta[:line] == 1
      assert b_meta[:closing][:line] == 2
    end

    test "propagates line corrections for Access :get" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a[b]"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:b, meta, context}, state ->
            {{:b, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., access_meta, [Access, :get]}, call_meta,
              [
                {:a, a_meta, _},
                {:b, b_meta, _}
              ]} = ast

      assert access_meta == call_meta
      assert a_meta[:line] == 1
      assert access_meta[:line] == 2
      assert b_meta[:line] == 2
      assert access_meta[:closing][:line] == 3

      {ast, _} =
        traverse(parse_string!("a.b[c]"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          :b, state ->
            {:b, %{state | line_correction: state.line_correction + 1}}

          {:c, meta, context}, state ->
            {{:c, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., access_meta, [Access, :get]}, access_meta,
              [
                {{:., dot_meta,
                  [
                    {:a, a_meta, nil},
                    :b
                  ]}, b_meta, []},
                {:c, c_meta, nil}
              ]} = ast

      assert a_meta[:line] == 1
      assert dot_meta[:line] == 2
      assert b_meta[:line] == 2
      assert access_meta[:line] == 3
      assert c_meta[:line] == 3
      assert access_meta[:closing][:line] == 4
    end

    test "propagates line corrections for qualified tuples" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a.{b}"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:b, meta, context}, state ->
            {{:b, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta, [{:a, a_meta, _}, :{}]}, call_meta,
              [
                {:b, b_meta, _}
              ]} = ast

      assert a_meta[:line] == 1
      assert dot_meta[:line] == 2
      assert b_meta[:line] == 2
      assert call_meta[:closing][:line] == 3
    end

    test "propagates line corrections for 2-tuples" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("{a, b}"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:__block__, block_meta,
              [
                {{:a, a_meta, _}, {:b, b_meta, _}}
              ]} = ast

      assert block_meta[:line] == 1
      assert a_meta[:line] == 1
      assert b_meta[:line] == 2
      assert block_meta[:closing][:line] == 2
    end

    test "propagates line corrections for n-tuples" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("{a, b, c}"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:b, meta, context}, state ->
            {{:b, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:{}, tuple_meta,
              [
                {:a, a_meta, _},
                {:b, b_meta, _},
                {:c, c_meta, _}
              ]} = ast

      assert tuple_meta[:line] == 1
      assert a_meta[:line] == 1
      assert b_meta[:line] == 2
      assert c_meta[:line] == 3
      assert tuple_meta[:closing][:line] == 3
    end

    test "propagates line corrections for maps" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("%{a, b, c}"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:%{}, map_meta,
              [
                {:a, a_meta, _},
                {:b, b_meta, _},
                {:c, c_meta, _}
              ]} = ast

      assert map_meta[:line] == 1
      assert a_meta[:line] == 1
      assert b_meta[:line] == 2
      assert c_meta[:line] == 2
      assert map_meta[:closing][:line] == 2
    end

    test "propagates line corrections for structs" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("%s{a, b, c}"), nil, noop, fn
          {:s, meta, context}, state ->
            {{:s, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:b, meta, context}, state ->
            {{:b, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:%, struct_meta,
              [
                {:s, s_meta, _},
                {:%{}, map_meta,
                 [
                   {:a, a_meta, _},
                   {:b, b_meta, _},
                   {:c, c_meta, _}
                 ]}
              ]} = ast

      assert struct_meta[:line] == 1
      assert s_meta[:line] == 1
      assert a_meta[:line] == 2
      assert b_meta[:line] == 3
      assert c_meta[:line] == 4
      assert map_meta[:closing][:line] == 4
    end

    test "propagates line corrections for lists" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("[a, b, c]"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:__block__, list_meta,
              [
                [
                  {:a, a_meta, _},
                  {:b, b_meta, _},
                  {:c, c_meta, _}
                ]
              ]} = ast

      assert list_meta[:line] == 1
      assert a_meta[:line] == 1
      assert b_meta[:line] == 2
      assert c_meta[:line] == 2
      assert list_meta[:closing][:line] == 2
    end

    test "propagates line corrections for do blocks" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a.b(c) do d end"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          :b, state ->
            {:b, %{state | line_correction: state.line_correction + 1}}

          {:c, meta, context}, state ->
            {{:c, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:d, meta, context}, state ->
            {{:d, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta,
               [
                 {:a, a_meta, _},
                 :b
               ]}, b_meta,
              [
                {:c, c_meta, _},
                [{{:__block__, do_meta, [:do]}, {:d, d_meta, _}}]
              ]} = ast

      assert a_meta[:line] == 1
      assert dot_meta[:line] == 2
      assert b_meta[:line] == 2
      assert c_meta[:line] == 3
      assert b_meta[:closing][:line] == 4
      assert b_meta[:do][:line] == 4
      assert do_meta[:line] == 4
      assert d_meta[:line] == 4
      assert b_meta[:end][:line] == 5
    end

    test "propagates line corrections for kw blocks" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a.b(c) do d after e end"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          :b, state ->
            {:b, %{state | line_correction: state.line_correction + 1}}

          {:c, meta, context}, state ->
            {{:c, meta, context}, %{state | line_correction: state.line_correction + 1}}

          {:d, meta, context}, state ->
            {{:d, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {{:., dot_meta,
               [
                 {:a, a_meta, _},
                 :b
               ]}, b_meta,
              [
                {:c, c_meta, _},
                [
                  {{:__block__, do_meta, [:do]}, {:d, d_meta, _}},
                  {{:__block__, after_meta, [:after]}, {:e, e_meta, _}}
                ]
              ]} = ast |> IO.inspect()

      assert a_meta[:line] == 1
      assert dot_meta[:line] == 2
      assert b_meta[:line] == 2
      assert c_meta[:line] == 3
      assert b_meta[:closing][:line] == 4
      assert b_meta[:do][:line] == 4
      assert do_meta[:line] == 4
      assert d_meta[:line] == 4
      assert after_meta[:line] == 5
      assert e_meta[:line] == 5
      assert b_meta[:end][:line] == 5
    end

    test "propagates line corrections in blocks" do
      noop = fn ast, state -> {ast, state} end

      {ast, _} =
        traverse(parse_string!("a\nb\nc"), nil, noop, fn
          {:a, meta, context}, state ->
            {{:a, meta, context}, %{state | line_correction: state.line_correction + 1}}

          ast, state ->
            {ast, state}
        end)

      assert {:__block__, _,
              [
                {:a, a_meta, _},
                {:b, b_meta, _},
                {:c, c_meta, _}
              ]} = ast

      assert a_meta[:line] == 1
      assert b_meta[:line] == 3
      assert c_meta[:line] == 4
    end

    defp prepend_ast(ast, state) do
      {ast, %{state | acc: [ast | state.acc]}}
    end

    defp traverse(ast) do
      traverse(ast, [], &prepend_ast/2, &prepend_ast/2)
      |> elem(1)
      |> Enum.reverse()
    end

    test "traverses the full ast" do
      assert traverse({:foo, [], nil}) == [{:foo, [], nil}, {:foo, [], nil}]

      assert traverse({:foo, [], [1, 2, 3]}) == [
               {:foo, [], [1, 2, 3]},
               1,
               1,
               2,
               2,
               3,
               3,
               {:foo, [], [1, 2, 3]}
             ]

      assert traverse({{:., [], [:foo, :bar]}, [], [1, 2, 3]}) ==
               [
                 {{:., [], [:foo, :bar]}, [], [1, 2, 3]},
                 {:., [], [:foo, :bar]},
                 :foo,
                 :foo,
                 :bar,
                 :bar,
                 {:., [], [:foo, :bar]},
                 1,
                 1,
                 2,
                 2,
                 3,
                 3,
                 {{:., [], [:foo, :bar]}, [], [1, 2, 3]}
               ]

      assert traverse({[1, 2, 3], [4, 5, 6]}) ==
               [
                 {[1, 2, 3], [4, 5, 6]},
                 [1, 2, 3],
                 1,
                 1,
                 2,
                 2,
                 3,
                 3,
                 [1, 2, 3],
                 [4, 5, 6],
                 4,
                 4,
                 5,
                 5,
                 6,
                 6,
                 [4, 5, 6],
                 {[1, 2, 3], [4, 5, 6]}
               ]
    end

    defp prewalk(ast) do
      Sourceror.prewalk(ast, [], &prepend_ast/2) |> elem(1) |> Enum.reverse()
    end

    test "prewalk/3" do
      assert prewalk({:foo, [], nil}) == [{:foo, [], nil}]

      assert prewalk({:foo, [], [1, 2, 3]}) == [{:foo, [], [1, 2, 3]}, 1, 2, 3]

      assert prewalk({{:., [], [:foo, :bar]}, [], [1, 2, 3]}) ==
               [
                 {{:., [], [:foo, :bar]}, [], [1, 2, 3]},
                 {:., [], [:foo, :bar]},
                 :foo,
                 :bar,
                 1,
                 2,
                 3
               ]

      assert prewalk({[1, 2, 3], [4, 5, 6]}) ==
               [{[1, 2, 3], [4, 5, 6]}, [1, 2, 3], 1, 2, 3, [4, 5, 6], 4, 5, 6]
    end

    defp postwalk(ast) do
      Sourceror.postwalk(ast, [], &prepend_ast/2) |> elem(1) |> Enum.reverse()
    end

    test "postwalk/3" do
      assert postwalk({:foo, [], nil}) == [{:foo, [], nil}]

      assert postwalk({:foo, [], [1, 2, 3]}) == [1, 2, 3, {:foo, [], [1, 2, 3]}]

      assert postwalk({{:., [], [:foo, :bar]}, [], [1, 2, 3]}) ==
               [
                 :foo,
                 :bar,
                 {:., [], [:foo, :bar]},
                 1,
                 2,
                 3,
                 {{:., [], [:foo, :bar]}, [], [1, 2, 3]}
               ]

      assert postwalk({[1, 2, 3], [4, 5, 6]}) ==
               [1, 2, 3, [1, 2, 3], 4, 5, 6, [4, 5, 6], {[1, 2, 3], [4, 5, 6]}]
    end
  end
end
