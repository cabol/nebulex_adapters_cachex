defmodule Nebulex.Adapters.Cachex.PersistenceErrorTest do
  import Nebulex.CacheCase

  deftests "persistence error" do
    test "dump: invalid path", %{cache: cache} do
      assert {:error, reason} = cache.dump("/invalid/path")
      assert reason in [:unreachable_file, :enoent]
    end

    test "load: invalid path", %{cache: cache} do
      assert {:error, reason} = cache.load("wrong_file")
      assert reason in [:unreachable_file, :enoent]
    end
  end
end
