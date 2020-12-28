defmodule NebulexAdaptersCachex.PartitionedTest do
  use Nebulex.NodeCase
  use Nebulex.Adapters.CachexTest

  alias NebulexAdaptersCachex.TestCache.Partitioned

  @primary :"primary@127.0.0.1"

  setup do
    cluster =
      :lists.usort([
        @primary
        | Application.get_env(:nebulex_adapters_cachex, :nodes, [])
      ])

    node_pid_list =
      start_caches(
        [node() | Node.list()],
        [{Partitioned, []}]
      )

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)

    {:ok, cache: Partitioned, name: Partitioned, cluster: cluster}
  end

  describe "partitioned cache" do
    test "get_and_update" do
      assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {nil, 1}
      assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {1, 2}
      assert Partitioned.get_and_update(1, &Partitioned.get_and_update_fun/1) == {2, 4}

      assert_raise ArgumentError, fn ->
        Partitioned.get_and_update(1, &Partitioned.get_and_update_bad_fun/1)
      end
    end
  end
end
