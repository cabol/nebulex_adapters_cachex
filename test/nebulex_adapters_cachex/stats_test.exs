defmodule NebulexAdaptersCachex.StatsTest do
  use ExUnit.Case, async: true

  import Nebulex.CacheCase

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Multilevel

    defmodule L1 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Cachex
    end

    defmodule L2 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Replicated,
        primary_storage_adapter: Nebulex.Adapters.Cachex
    end

    defmodule L3 do
      use Nebulex.Cache,
        otp_app: :nebulex,
        adapter: Nebulex.Adapters.Partitioned,
        primary_storage_adapter: Nebulex.Adapters.Cachex
    end
  end

  @config [
    model: :inclusive,
    levels: [
      {Cache.L1, []},
      {Cache.L2, []},
      {Cache.L3, []}
    ]
  ]

  describe "stats/0" do
    setup_with_cache(Cache, [stats: true] ++ @config)

    test "hits and misses" do
      :ok = Cache.put_all(a: 1, b: 2)

      assert Cache.get(:a) == 1
      assert Cache.has_key?(:a)
      assert Cache.ttl(:b) == :infinity
      refute Cache.get(:c)
      refute Cache.get(:d)

      assert_stats_measurements(Cache,
        l1: [hits: 3, misses: 2, writes: 2],
        l2: [hits: 0, misses: 2, writes: 2],
        l3: [hits: 0, misses: 2, writes: 2]
      )
    end

    test "writes and updates" do
      assert Cache.put_all(a: 1, b: 2) == :ok
      refute Cache.put_new_all(a: 1, b: 2)
      assert Cache.put_new_all(c: 3, d: 4, e: 3)
      assert Cache.put(1, 1) == :ok
      refute Cache.put_new(1, 2)
      refute Cache.replace(2, 2)
      assert Cache.put_new(2, 2)
      assert Cache.replace(2, 22)
      assert Cache.incr(:counter) == 1
      assert Cache.incr(:counter) == 2
      refute Cache.expire(:f, 1000)
      assert Cache.expire(:a, 1000)
      refute Cache.touch(:f)
      assert Cache.touch(:b)

      :ok = Process.sleep(1100)
      refute Cache.get(:a)

      assert_stats_measurements(Cache,
        l1: [expirations: 1, misses: 5, writes: 8, updates: 4],
        l2: [expirations: 1, misses: 5, writes: 8, updates: 4],
        l3: [expirations: 1, misses: 5, writes: 8, updates: 4]
      )
    end

    test "evictions" do
      entries = for x <- 1..10, do: {x, x}
      :ok = Cache.put_all(entries)

      assert Cache.delete(1) == :ok
      assert Cache.take(2) == 2
      refute Cache.take(20)

      assert_stats_measurements(Cache,
        l1: [evictions: 2, misses: 1, writes: 10],
        l2: [evictions: 2, misses: 1, writes: 10],
        l3: [evictions: 2, misses: 1, writes: 10]
      )

      assert Cache.delete_all() == 24

      assert_stats_measurements(Cache,
        l1: [evictions: 10, misses: 1, writes: 10],
        l2: [evictions: 10, misses: 1, writes: 10],
        l3: [evictions: 10, misses: 1, writes: 10]
      )
    end

    test "expirations" do
      :ok = Cache.put_all(a: 1, b: 2)
      :ok = Cache.put_all([c: 3, d: 4], ttl: 1000)

      assert Cache.get_all([:a, :b, :c, :d]) == %{a: 1, b: 2, c: 3, d: 4}

      :ok = Process.sleep(1100)
      assert Cache.get_all([:a, :b, :c, :d]) == %{a: 1, b: 2}

      assert_stats_measurements(Cache,
        l1: [evictions: 2, expirations: 2, hits: 6, misses: 2, writes: 4],
        l2: [evictions: 2, expirations: 2, hits: 0, misses: 2, writes: 4],
        l3: [evictions: 2, expirations: 2, hits: 0, misses: 2, writes: 4]
      )
    end
  end

  ## Helpers

  defp assert_stats_measurements(cache, levels) do
    measurements = cache.stats().measurements

    for {level, stats} <- levels, {stat, expected} <- stats do
      assert get_in(measurements, [level, stat]) == expected
    end
  end
end
