defmodule Nebulex.Adapters.CachexTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.EntryTest
      use Nebulex.Cache.TransactionTest
      use Nebulex.Cache.PersistenceTest
      use Nebulex.Adapters.Cachex.EntryExpirationTest
      use Nebulex.Adapters.Cachex.QueryableTest
      use Nebulex.Adapters.Cachex.PersistenceErrorTest
    end
  end
end
