defmodule Nebulex.Adapters.Cachex.QueryableTest do
  import Nebulex.CacheCase

  deftests "queryable" do
    import Nebulex.CacheHelpers

    alias Cachex.Query

    test "all", %{cache: cache} do
      set1 = cache_put(cache, 1..50)
      set2 = cache_put(cache, 51..100)

      for x <- 1..100, do: assert(cache.get(x) == x)
      expected = set1 ++ set2

      assert :lists.usort(cache.all()) == expected

      set3 = Enum.to_list(20..60)
      :ok = Enum.each(set3, &cache.delete(&1))
      expected = :lists.usort(expected -- set3)

      assert :lists.usort(cache.all()) == expected
    end

    test "stream", %{cache: cache} do
      entries = for x <- 1..10, into: %{}, do: {x, x * 2}
      assert cache.put_all(entries) == :ok

      expected = Map.keys(entries)

      assert true
             |> Query.create(:key)
             |> cache.stream()
             |> Enum.to_list()
             |> :lists.usort() == expected

      assert true
             |> Query.create(:key)
             |> cache.stream(page_size: 3)
             |> Enum.to_list()
             |> :lists.usort() == expected

      assert_raise Nebulex.QueryError, fn ->
        :invalid_query
        |> cache.stream()
        |> Enum.to_list()
      end
    end
  end
end
