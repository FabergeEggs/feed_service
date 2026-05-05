defmodule FeedService.Feed.MediaEnrichment do
  @moduledoc """
  Resolves `feed_item.media_ids` into compact metadata via media_service,
  with a per-asset Redis cache. Errors degrade silently — feed responses
  never fail because media is unreachable.
  """

  alias FeedService.Cache
  alias FeedService.Clients.MediaClient
  alias FeedService.Feed.FeedItem

  @cache_ttl 300

  @doc """
  Returns `%{asset_id => meta | nil}` for every id referenced in `items`.
  """
  @spec for_items([FeedItem.t()]) :: %{String.t() => map() | nil}
  def for_items(items) when is_list(items) do
    items
    |> collect_ids()
    |> resolve()
  end

  defp collect_ids(items) do
    items
    |> Enum.flat_map(fn %FeedItem{media_ids: ids} -> ids || [] end)
    |> Enum.uniq()
  end

  defp resolve([]), do: %{}

  defp resolve(ids) do
    {hits, misses} = split_by_cache(ids)
    fresh = fetch_fresh(misses)

    Enum.each(fresh, fn
      {id, meta} when is_map(meta) -> Cache.put(cache_key(id), meta, @cache_ttl)
      _ -> :ok
    end)

    Map.merge(hits, fresh)
  end

  defp split_by_cache(ids) do
    Enum.reduce(ids, {%{}, []}, fn id, {hits, misses} ->
      case Cache.get(cache_key(id)) do
        {:ok, meta} -> {Map.put(hits, id, meta), misses}
        _ -> {hits, [id | misses]}
      end
    end)
  end

  defp fetch_fresh([]), do: %{}

  defp fetch_fresh(ids) do
    results = MediaClient.batch_get_assets(ids)

    Map.new(ids, fn id ->
      case Map.get(results, id) do
        {:ok, body} -> {id, normalize(body)}
        _ -> {id, nil}
      end
    end)
  end

  defp normalize(%{"asset" => asset}), do: normalize(asset)

  defp normalize(asset) when is_map(asset) do
    mime = asset["detected_mime"] || asset["declared_mime"]

    %{
      "id" => asset["id"],
      "kind" => kind_from_mime(mime),
      "mime" => mime,
      "size_bytes" => asset["size_bytes"],
      "status" => asset["status"]
    }
  end

  defp normalize(_), do: nil

  defp kind_from_mime("image/" <> _), do: "image"
  defp kind_from_mime("video/" <> _), do: "video"
  defp kind_from_mime("audio/" <> _), do: "audio"
  defp kind_from_mime(_), do: "file"

  defp cache_key(id), do: "media:asset:#{id}"
end
