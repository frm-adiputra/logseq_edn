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
    :"logseq.property.class/properties",
    :"logseq.property/closed-values"
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
    |> Enum.reduce(%{}, fn x, acc -> Map.put(acc, x.block_num, x) end)
  end

  def root_tag(blocks) do
    case Enum.find(blocks, fn {_, v} -> v[:"block/name"] == "root tag" end) do
      {_block_num, block} -> block
      nil -> nil
    end
  end

  @doc """
  Get all blocks that extend the given block number.
  """
  def extension_of(blocks, block_num) do
    Enum.filter(blocks, fn {_, v} ->
      if Map.has_key?(v, :"logseq.property.class/extends") do
        block_num in v[:"logseq.property.class/extends"]
      else
        false
      end
    end)
    |> Enum.map(fn {_, v} -> v end)
  end

  @doc """
  Get all tags.
  """
  def tag_blocks(blocks) do
    root_tag_block = LogseqEdn.root_tag(blocks)
    LogseqEdn.extension_of(blocks, root_tag_block.block_num)
  end

  @doc """
  Get all blocks that are tagged with the given tags. Raises an error if any of the tags are not found in the available tags.
  """
  def tagged_with!(blocks, tags) do
    available_tags = tag_blocks(blocks)

    available_tags_title_set =
      Enum.map(available_tags, fn v -> v[:"block/title"] end) |> MapSet.new()

    tags_set = MapSet.new(tags)
    diff = MapSet.difference(tags_set, available_tags_title_set)

    if MapSet.size(diff) > 0 do
      raise "Tags #{inspect(diff)} not found in available tags"
    end

    tag_nums =
      Enum.filter(available_tags, fn v -> v[:"block/title"] in tags end)
      |> Enum.map(fn x -> x.block_num end)
      |> MapSet.new()

    Enum.filter(blocks, fn {_, v} ->
      if Map.has_key?(v, :"block/tags") do
        MapSet.subset?(tag_nums, MapSet.new(v[:"block/tags"]))
      else
        false
      end
    end)
    |> Enum.map(fn {_, v} -> v end)
  end

  @doc """
  Build a tree structure from the given block list.
  """
  def tree(blocks, block_list) when is_list(block_list) do
    Enum.map(block_list, fn block -> do_tree(blocks, block) end)
  end

  defp do_tree(blocks, block) do
    children =
      Enum.filter(blocks, fn {_, v} ->
        if Map.has_key?(v, :"block/parent") do
          v[:"block/parent"] == block.block_num
        else
          false
        end
      end)
      |> Enum.map(fn {_, v} -> v end)

    if length(children) > 0 do
      ch = tree(blocks, children)
      Map.put(block, :children, ch)
    else
      Map.put(block, :children, children)
    end
  end

  @doc """
  Convert the given tree structure to a markdown string.
  """
  def to_markdown(tree, level \\ 0) do
    Enum.map(tree, fn block -> do_to_markdown(block, level) end)
    |> Enum.join("\n")
  end

  defp do_to_markdown(block, level) do
    markdown_text =
      "#{String.duplicate("  ", level)}- #{Macro.unescape_string(block[:"block/title"]) |> String.replace("\n", "\n" <> String.duplicate("  ", level + 1))}\n"

    if block[:children] == [] do
      markdown_text
    else
      markdown_text_children = to_markdown(block[:children], level + 1)
      Enum.join([markdown_text, markdown_text_children], "\n")
    end
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
