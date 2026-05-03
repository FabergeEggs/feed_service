defmodule FeedService.Cache do
  @moduledoc """
  Thin wrapper around Redix for caching feed timelines and profile lookups.

  Values are serialized with `:erlang.term_to_binary/1`. We only ever
  read what we wrote, so we don't need the `:safe` flag on the way back.
  This format is faster than JSON and preserves Elixir structs (DateTime,
  Ecto schemas, etc) without per-call (de)coders.

  All Redis errors surface as `{:error, term}` — callers should treat the
  cache as a best-effort optimization and fall back to the source of
  truth (Postgres) when it is unreachable.
  """

  @conn FeedService.Redix

  @type key :: String.t()
  @type value :: term()
  @type ttl :: pos_integer()

  @doc """
  Looks up a key.

    * `{:ok, value}` — hit
    * `:miss`        — key not found
    * `{:error, _}`  — Redis unreachable / protocol error
  """
  @spec get(key()) :: {:ok, value()} | :miss | {:error, term()}
  def get(key) do
    case Redix.command(@conn, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, bin} when is_binary(bin) -> {:ok, :erlang.binary_to_term(bin)}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Stores `value` under `key` with a TTL in seconds."
  @spec put(key(), value(), ttl()) :: :ok | {:error, term()}
  def put(key, value, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
    bin = :erlang.term_to_binary(value)

    case Redix.command(@conn, ["SET", key, bin, "EX", Integer.to_string(ttl_seconds)]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "Removes one key. Returns `:ok` whether or not the key existed."
  @spec delete(key()) :: :ok | {:error, term()}
  def delete(key) do
    case Redix.command(@conn, ["DEL", key]) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Removes every key matching a glob pattern (e.g. `"feed:user:abc:*"`).
  Uses `SCAN` to avoid blocking Redis on large keyspaces.
  """
  @spec invalidate_pattern(String.t()) :: :ok | {:error, term()}
  def invalidate_pattern(pattern), do: scan_and_delete(pattern, "0")

  defp scan_and_delete(pattern, cursor) do
    case Redix.command(@conn, ["SCAN", cursor, "MATCH", pattern, "COUNT", "100"]) do
      {:ok, [next_cursor, keys]} ->
        if keys != [], do: Redix.command(@conn, ["DEL" | keys])

        if next_cursor == "0" do
          :ok
        else
          scan_and_delete(pattern, next_cursor)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
