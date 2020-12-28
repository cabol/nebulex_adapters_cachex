defmodule NebulexAdaptersCachex.MultilevelTest do
  use ExUnit.Case, async: true
  use Nebulex.NodeCase
  use Nebulex.MultilevelTest
  # use Nebulex.Cache.QueryableTest
  # use Nebulex.Cache.TransactionTest

  import Nebulex.CacheCase

  alias Nebulex.Time
  alias NebulexAdaptersCachex.TestCache.Multilevel
  alias NebulexAdaptersCachex.TestCache.Multilevel.{L1, L2, L3}

  @gc_interval Time.expiry_time(1, :hour)

  @levels [
    {
      L1,
      name: :multilevel_inclusive_l1, gc_interval: @gc_interval
    },
    {
      L2,
      name: :multilevel_inclusive_l2, primary: [gc_interval: @gc_interval]
    },
    {
      L3,
      name: :multilevel_inclusive_l3, primary: [gc_interval: @gc_interval]
    }
  ]

  setup_with_dynamic_cache(Multilevel, :multilevel_inclusive,
    model: :inclusive,
    levels: @levels
  )
end
