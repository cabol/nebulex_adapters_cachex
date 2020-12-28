defmodule NebulexAdaptersCachex.LocalTest do
  use ExUnit.Case, async: true
  use Nebulex.Adapters.CachexTest

  import Nebulex.CacheCase

  alias NebulexAdaptersCachex.TestCache.Local, as: Cache

  setup_with_dynamic_cache(Cache, :local_with_cachex)
end
