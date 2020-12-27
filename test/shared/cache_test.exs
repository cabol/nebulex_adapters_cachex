defmodule NebulexCachexAdapter.CacheTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.EntryTest
      use Nebulex.Cache.EntryExpirationTest
      use NebulexCachexAdapter.QueryableTest
    end
  end
end
