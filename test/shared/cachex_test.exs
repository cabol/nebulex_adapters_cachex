defmodule Nebulex.Adapters.CachexTest do
  @moduledoc """
  Shared Tests
  """

  defmacro __using__(_opts) do
    quote do
      use Nebulex.Cache.EntryTest
      use Nebulex.Cache.EntryExpirationTest
      use Nebulex.Adapters.Cachex.QueryableTest
    end
  end
end
