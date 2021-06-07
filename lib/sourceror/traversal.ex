defmodule Sourceror.Traversal do
  @moduledoc false

  import Sourceror, only: [correct_lines: 2, correct_lines: 3]

  defmodule State do
    import Sourceror.Utils.TypedStruct

    typedstruct do
      field :acc, term()
      field :line_correction, integer(), default: 0
    end
  end

  # @line_fields ~w[closing do end end_of_expression]a
  # @start_fields ~w[line do]a
  @end_fields ~w[end closing end_of_expression]a

  def traverse(ast, acc, pre, post) when is_function(pre, 2) and is_function(post, 2) do
    state = %State{acc: acc}
    {ast, state} = pre.(ast, state)
    {ast, %{acc: acc}} = do_traverse(ast, state, pre, post)
    {ast, acc}
  end

  # Variables
  defp do_traverse({form, meta, context}, state, _pre, post) when is_atom(context) do
    post.({form, meta, context}, state)
  end

  defp do_traverse({:__block__, meta, [literal]}, state, pre, post)
       when not is_tuple(literal) or tuple_size(literal) == 2 do
    {literal, state} = pre.(literal, state)
    {literal, state} = do_traverse(literal, state, pre, post)

    meta = correct_ending_lines(meta, state)

    post.({:__block__, meta, [literal]}, state)
  end

  defp do_traverse({:__block__, meta, args}, state, pre, post) do
    meta = correct_starting_lines(meta, state)
    {args, state} = do_traverse_args(args, state, pre, post)

    meta = correct_ending_lines(meta, state)

    post.({:__block__, meta, args}, state)
  end

  defp do_traverse({form, meta, args}, state, pre, post) when form in [:{}, :%{}] do
    {args, state} = do_traverse_args(args, state, pre, post)

    meta = correct_ending_lines(meta, state)

    post.({form, meta, args}, state)
  end

  defp do_traverse({:%, meta, [struct, map]}, state, pre, post) do
    {struct, state} = pre.(struct, state)
    {struct, state} = do_traverse(struct, state, pre, post)

    {map, state} = pre.(map, state)
    {map, state} = do_traverse(map, state, pre, post)

    post.({:%, meta, [struct, map]}, state)
  end

  # a(b)
  defp do_traverse({form, meta, args}, state, pre, post) when is_atom(form) do
    original_correction = state.line_correction

    if meta[:do] do
      {kw, args} = List.pop_at(args, -1)

      {args, args_state} = do_traverse_args(args, state, pre, post)

      meta =
        meta
        |> correct_line(:closing, args_state)
        |> correct_line(:do, args_state)

      kw = correct_lines(kw, args_state.line_correction)
      {kw, args_state} = pre.(kw, args_state)
      {kw, args_state} = do_traverse(kw, args_state, pre, post)

      meta = correct_line(meta, :end, args_state)

      args = args ++ [kw]

      state = %{args_state | line_correction: state.line_correction}

      {{form, meta, args}, state} = post.({form, meta, args}, state)

      meta =
        meta
        |> correct_line(:closing, state)
        |> correct_line(:do, state)
        |> correct_line(:end, state)

      ast =
        Sourceror.update_args(
          {form, meta, args},
          &recursive_correct_lines(&1, state.line_correction)
        )

      outer_correction = state.line_correction - original_correction
      args_correction = args_state.line_correction - original_correction

      line_correction = original_correction + outer_correction + args_correction

      state = %{args_state | line_correction: line_correction}

      {ast, state}
    else
      {args, state} = do_traverse_args(args, state, pre, post)

      {ast, state} = post.({form, meta, args}, state)

      {Sourceror.update_args(ast, &recursive_correct_lines(&1, state.line_correction)), state}
    end
  end

  # left[right]
  defp do_traverse(
         {{:., access_meta, [Access, :get]}, call_meta, [left, right]},
         state,
         pre,
         post
       ) do
    {left, state} = pre.(left, state)
    {left, state} = do_traverse(left, state, pre, post)
    access_meta = correct_starting_lines(access_meta, state)
    call_meta = correct_starting_lines(call_meta, state)
    right = correct_lines(right, state.line_correction)

    {right, state} = pre.(right, state)
    {right, state} = do_traverse(right, state, pre, post)
    access_meta = correct_ending_lines(access_meta, state)
    call_meta = correct_ending_lines(call_meta, state)

    post.({{:., access_meta, [Access, :get]}, call_meta, [left, right]}, state)
  end

  # left.right(args)
  # left.right(args) do ... end
  defp do_traverse({{:., dot_meta, [left, right]}, right_meta, args}, state, pre, post) do
    {{:., dot_meta, [left, right]}, state} = pre.({:., dot_meta, [left, right]}, state)

    {left, state} = pre.(left, state)
    {left, state} = do_traverse(left, state, pre, post)
    dot_meta = correct_lines(dot_meta, state.line_correction)

    right_meta =
      if right_meta[:line] do
        Keyword.update!(right_meta, :line, &(&1 + state.line_correction))
      else
        right_meta
      end

    {right, state} = pre.(right, state)
    {right, state} = do_traverse(right, state, pre, post)

    {dot, state} = post.({:., dot_meta, [left, right]}, state)

    if right_meta[:do] do
      {kw, args} = List.pop_at(args, -1)

      {args, state} = do_traverse_args(args, state, pre, post)

      right_meta =
        right_meta
        |> correct_line(:closing, state)
        |> correct_line(:do, state)

      kw = correct_lines(kw, state.line_correction)
      {kw, state} = pre.(kw, state)
      {kw, state} = do_traverse(kw, state, pre, post)

      right_meta = correct_line(right_meta, :end, state)

      args = args ++ [kw]

      post.({dot, right_meta, args}, state)
    else
      {args, state} = do_traverse_args(args, state, pre, post)

      right_meta = correct_ending_lines(right_meta, state)

      post.({{:., dot_meta, [left, right]}, right_meta, args}, state)
    end
  end

  defp do_traverse({left, right}, state, pre, post) do
    {left, state} = pre.(left, state)
    {left, state} = do_traverse(left, state, pre, post)

    right = correct_lines(right, state.line_correction)
    {right, state} = pre.(right, state)
    {right, state} = do_traverse(right, state, pre, post)

    post.({left, right}, state)
  end

  defp do_traverse(list, state, pre, post) when is_list(list) do
    {list, state} = do_traverse_args(list, state, pre, post)
    post.(list, state)
  end

  defp do_traverse(ast, state, _pre, post) do
    post.(ast, state)
  end

  defp do_traverse_args(args, state, _pre, _post) when is_atom(args) do
    {args, state}
  end

  defp do_traverse_args(args, state, pre, post) when is_list(args) do
    Enum.map_reduce(args, state, fn
      ast, state ->
        ast = correct_lines(ast, state.line_correction)
        {ast, state} = pre.(ast, state)
        do_traverse(ast, state, pre, post)
    end)
  end

  defp correct_line(meta, key, state) do
    if meta[key] do
      update_in(meta, [key, :line], &(&1 + state.line_correction))
    else
      meta
    end
  end

  defp correct_starting_lines(quoted_or_meta, state) do
    correct_lines(quoted_or_meta, state.line_correction, skip: [:trailing_comments] ++ @end_fields)
  end

  defp correct_ending_lines(quoted_or_meta, state) do
    correct_lines(quoted_or_meta, state.line_correction, skip: [:leading_comments, :line, :do])
  end

  defp recursive_correct_lines(ast, line_correction) do
    Macro.postwalk(ast, fn
      {_, _, _} = ast ->
        correct_lines(ast, line_correction)

      ast ->
        ast
    end)
  end
end
