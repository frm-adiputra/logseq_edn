defmodule LogseqEdn do
  @moduledoc """
  Documentation for `LogseqEdn`.

  For more information about the Logseq database query, please refer to the official documentation:
  https://github.com/logseq/logseq/blob/4975d5c21398d6173a2ef4444cb0f7c44817000e/libs/guides/db_query_guide.md?plain=1#L130
  """

  @list_attributes [
    :"block/refs",
    :"block/tags",
    :"logseq.property.class/extends",
    :"logseq.property.class/properties"
  ]

  @doc """
  Parse the given EDN file and return a map of block number and its data.
  """
  def parse(filename) do
    edn =
      File.read!(filename)
      |> Exdn.to_elixir!()

    edn.datoms
    |> Enum.group_by(&Enum.at(&1, 0))
    |> Enum.map(&parse_block/1)
  end

  defp parse_block({k, v}) do
    Enum.reduce(v, %{block_num: k}, fn attr_list, acc ->
      parse_attribute(attr_list, acc)
    end)
  end

  defp parse_attribute([_block_num, attr, value], block_map) do
    if attr in @list_attributes do
      put_in_list(block_map, attr, value)
    else
      put_value(block_map, attr, value)
    end
  end

  defp put_value(block_map, key, value) do
    if Map.has_key?(block_map, key) do
      raise "Duplicate key #{key} found in block map: #{inspect(block_map)}"
    else
      Map.put(block_map, key, value)
    end
  end

  defp put_in_list(block_map, key, value) do
    if Map.has_key?(block_map, key) do
      Map.update!(block_map, key, fn existing_value ->
        List.wrap(existing_value) ++ [value]
      end)
    else
      Map.put(block_map, key, [value])
    end
  end
end
