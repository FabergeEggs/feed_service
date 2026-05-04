defmodule FeedService.Cache do
  @moduledoc "Redix-backed cache. ETF serialization. Errors return `{:error, _}` — callers degrade gracefully."

  @conn FeedService.Redix

  @type key :: String.t()
  @type value :: term()
  @type ttl :: pos_integer()

  @spec get(key()) :: {:ok, value()} | :miss | {:error, term()}
  def get(key) do
    case Redix.command(@conn, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, bin} when is_binary(bin) -> {:ok, :erlang.binary_to_term(bin)}
      {:error, reason} -> {:error, reason}
    end
  end

  @spec put(key(), value(), ttl()) :: :ok | {:error, term()}
  def put(key, value, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
    bin = :erlang.term_to_binary(value)

    case Redix.command(@conn, ["SET", key, bin, "EX", Integer.to_string(ttl_seconds)]) do
      {:ok, "OK"} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @spec delete(key()) :: :ok | {:error, term()}
  def delete(key) do
    case Redix.command(@conn, ["DEL", key]) do
      {:ok, _count} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

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
