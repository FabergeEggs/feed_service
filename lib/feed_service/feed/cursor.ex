defmodule FeedService.Feed.Cursor do
  @moduledoc """
  Opaque keyset cursor for timeline pagination.

  Encodes the `(occurred_at, id)` pair of the last seen `FeedItem` into
  a URL-safe base64 string. Clients pass it back unchanged on the next
  request — the format is opaque and can change without breaking the API.

  The pair is the tie-breaker pattern: `id` disambiguates rows that
  share `occurred_at` to the microsecond, so no row is skipped or
  duplicated across pages.
  """

  @type t :: String.t()
  @type point :: {DateTime.t(), Ecto.UUID.t()}

  @doc "Encodes a cursor point. Returns a URL-safe base64 string."
  @spec encode(point()) :: t()
  def encode({%DateTime{} = at, id}) when is_binary(id) do
    %{"t" => DateTime.to_iso8601(at), "id" => id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Decodes a cursor string.

    * `nil` or `""` → `{:ok, nil}` (caller treats as "first page")
    * valid cursor  → `{:ok, {datetime, uuid}}`
    * tampered or malformed input → `:error`
  """
  @spec decode(t() | nil) :: {:ok, point() | nil} | :error
  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"t" => t, "id" => id}} <- Jason.decode(json),
         {:ok, datetime, _utc_offset} <- DateTime.from_iso8601(t),
         {:ok, _} <- Ecto.UUID.cast(id) do
      {:ok, {datetime, id}}
    else
      _ -> :error
    end
  end

  def decode(_), do: :error
end
