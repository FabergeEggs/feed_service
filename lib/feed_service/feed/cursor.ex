defmodule FeedService.Feed.Cursor do
  @moduledoc "Opaque keyset cursor encoding `{occurred_at, id}` as URL-safe base64."

  @type t :: String.t()
  @type point :: {DateTime.t(), Ecto.UUID.t()}

  @spec encode(point()) :: t()
  def encode({%DateTime{} = at, id}) when is_binary(id) do
    %{"t" => DateTime.to_iso8601(at), "id" => id}
    |> Jason.encode!()
    |> Base.url_encode64(padding: false)
  end

  @spec decode(t() | nil) :: {:ok, point() | nil} | :error
  def decode(nil), do: {:ok, nil}
  def decode(""), do: {:ok, nil}

  def decode(cursor) when is_binary(cursor) do
    with {:ok, json} <- Base.url_decode64(cursor, padding: false),
         {:ok, %{"t" => t, "id" => id}} <- Jason.decode(json),
         {:ok, datetime, _offset} <- DateTime.from_iso8601(t),
         {:ok, _} <- Ecto.UUID.cast(id) do
      {:ok, {datetime, id}}
    else
      _ -> :error
    end
  end

  def decode(_), do: :error
end
