defmodule Nebulex.Adapters.Cachex.QueryableTest do
  import Nebulex.CacheCase

  deftests do
    import Nebulex.CacheCase

    alias Cachex.Query

    describe "all/2" do
      test "returns all keys in cache", %{cache: cache} do
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
    end

    describe "delete_all/2" do
      test "removes all expired entries", %{cache: cache} do
        _ = cache_put(cache, 1..5, & &1, ttl: 1500)
        _ = cache_put(cache, 6..10)

        assert cache.delete_all(:expired) == 0
        assert cache.count_all() == 10

        :ok = Process.sleep(1600)

        assert cache.delete_all(:expired) == 5
        assert cache.count_all() == 5
      end
    end

    describe "stream/2" do
      @entries for x <- 1..10, into: %{}, do: {x, x * 2}

      test "returns all keys in cache", %{cache: cache} do
        :ok = cache.put_all(@entries)

        assert nil
               |> cache.stream(return: :key)
               |> Enum.to_list()
               |> :lists.usort() == Map.keys(@entries)
      end

      test "returns all values in cache", %{cache: cache} do
        :ok = cache.put_all(@entries)

        assert true
               |> Query.create(:key)
               |> cache.stream(return: :value, page_size: 3)
               |> Enum.to_list()
               |> :lists.usort() == Map.values(@entries)
      end

      test "returns all key/value pairs in cache", %{cache: cache} do
        :ok = cache.put_all(@entries)

        assert true
               |> Query.create(:key)
               |> cache.stream(return: {:key, :value}, page_size: 3)
               |> Enum.to_list()
               |> :lists.usort() == :maps.to_list(@entries)
      end

      test "returns what is dictated by the built query", %{cache: cache} do
        :ok = cache.put_all(@entries)

        expected =
          :lists.zip3(
            Map.keys(@entries),
            Map.values(@entries),
            List.duplicate(nil, map_size(@entries))
          )

        assert true
               |> Query.create({:key, :value, :ttl})
               |> cache.stream(page_size: 3)
               |> Enum.to_list()
               |> :lists.usort() == expected
      end

      test "raises when query is invalid", %{cache: cache} do
        assert_raise Nebulex.QueryError, fn ->
          :invalid_query
          |> cache.stream()
          |> Enum.to_list()
        end
      end
    end
  end
end
