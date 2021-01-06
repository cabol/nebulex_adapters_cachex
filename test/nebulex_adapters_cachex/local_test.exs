defmodule NebulexAdaptersCachex.LocalTest do
  use ExUnit.Case, async: true
  use Nebulex.Adapters.CachexTest

  import Nebulex.CacheCase

  alias NebulexAdaptersCachex.TestCache.Local, as: Cache

  setup_with_dynamic_cache(Cache, :local_with_cachex)

  describe "count_all/2 error:" do
    test "unsupported query", %{cache: cache} do
      assert_raise Nebulex.QueryError, ~r"unsupported count_all in query", fn ->
        cache.count_all(:unexpired)
      end
    end
  end

  describe "delete_all/2 error:" do
    test "unsupported query", %{cache: cache} do
      assert_raise Nebulex.QueryError, ~r"unsupported delete_all in query", fn ->
        cache.delete_all(:unexpired)
      end
    end
  end
end
