defmodule NebulexCachexAdapter.LocalTest do
  use ExUnit.Case, async: true
  use NebulexCachexAdapter.CacheTest

  import Nebulex.CacheCase

  alias NebulexCachexAdapter.TestCache.Local, as: Cache

  setup_with_dynamic_cache(Cache, :local_with_cachex)
end
