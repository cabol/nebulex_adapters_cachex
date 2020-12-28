defmodule NebulexAdaptersCachex.ReplicatedTest do
  use Nebulex.NodeCase
  use Nebulex.Adapters.CachexTest

  alias NebulexAdaptersCachex.TestCache.Replicated

  setup do
    node_pid_list = start_caches([node() | Node.list()], [{Replicated, []}])

    on_exit(fn ->
      :ok = Process.sleep(100)
      stop_caches(node_pid_list)
    end)

    {:ok, cache: Replicated, name: Replicated}
  end
end
