defmodule ExUnitOpenAPI.SchemaFingerprint do
  @moduledoc """
  Computes canonical fingerprints for JSON Schema identity comparison.

  Fingerprints are deterministic hashes that identify structurally identical
  schemas regardless of property order or formatting differences.

  ## Example

      schema1 = %{"type" => "object", "properties" => %{"a" => ..., "b" => ...}}
      schema2 = %{"type" => "object", "properties" => %{"b" => ..., "a" => ...}}

      # Same fingerprint - property order doesn't matter
      fingerprint(schema1) == fingerprint(schema2)
  """

  @type fingerprint :: String.t()

  @doc """
  Computes a SHA256 fingerprint for a JSON Schema.

  The fingerprint is deterministic - identical schemas always produce
  the same fingerprint regardless of key ordering.

  ## Examples

      iex> SchemaFingerprint.fingerprint(%{"type" => "string"})
      "A1B2C3..."  # 64 character hex string

      iex> schema1 = %{"properties" => %{"a" => %{}, "b" => %{}}}
      iex> schema2 = %{"properties" => %{"b" => %{}, "a" => %{}}}
      iex> SchemaFingerprint.fingerprint(schema1) == SchemaFingerprint.fingerprint(schema2)
      true
  """
  @spec fingerprint(map()) :: fingerprint()
  def fingerprint(schema) when is_map(schema) do
    schema
    |> normalize()
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  def fingerprint(_), do: ""

  @doc """
  Checks if two schemas have the same fingerprint.

  ## Examples

      iex> SchemaFingerprint.same?(schema1, schema2)
      true
  """
  @spec same?(map(), map()) :: boolean()
  def same?(schema1, schema2) do
    fingerprint(schema1) == fingerprint(schema2)
  end

  # Normalizes a schema into a canonical form for fingerprinting.
  # - Sorts map keys alphabetically at all levels
  # - Recursively normalizes nested schemas
  # - Converts to consistent Elixir terms
  @spec normalize(term()) :: term()
  defp normalize(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} ->
      {normalize_key(key), normalize(value)}
    end)
    |> Enum.sort_by(fn {key, _value} -> key end)
  end

  defp normalize(list) when is_list(list) do
    Enum.map(list, &normalize/1)
  end

  defp normalize(value), do: value

  # Ensures consistent key representation (strings)
  defp normalize_key(key) when is_atom(key), do: Atom.to_string(key)
  defp normalize_key(key) when is_binary(key), do: key
  defp normalize_key(key), do: inspect(key)
end
