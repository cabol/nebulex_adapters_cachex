defmodule Nebulex.Adapters.Cachex do
  @moduledoc """
  Nebulex adapter for [Cachex][Cachex].

  [Cachex]: http://hexdocs.pm/cachex/Cachex.html

  By means of this adapter, you can configure Cachex as the cache backend
  and use it through the Nebulex API.

  ## Options

  Since Nebulex is just a wrapper on top of Cachex, the options are the same as
  [Cachex.start_link/1][cachex_start_link].

  [cachex_start_link]: https://hexdocs.pm/cachex/Cachex.html#start_link/1

  ## Example

  You can define a cache using Cachex as follows:

      defmodule MyApp.Cache do
        use Nebulex.Cache,
          otp_app: :my_app,
          adapter: Nebulex.Adapters.Cachex
      end

  Where the configuration for the cache must be in your application
  environment, usually defined in your `config/config.exs`:

      config :my_app, MyApp.Cache,
        limit: 1_000_000,
        stats: true,
        ...

  If your application was generated with a supervisor (by passing `--sup`
  to `mix new`) you will have a `lib/my_app/application.ex` file containing
  the application start callback that defines and starts your supervisor.
  You just need to edit the `start/2` function to start the cache as a
  supervisor on your application's supervisor:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, []},
        ]

        ...
      end

  Since Cachex uses macros for some configuration options, you could also
  pass the options in runtime when the cache is started, either by calling
  `MyApp.Cache.start_link/1` directly, or in your app supervision tree:

      def start(_type, _args) do
        children = [
          {MyApp.Cache, cachex_opts()},
        ]

        ...
      end

      defp cachex_opts do
        import Cachex.Spec

        [
          expiration: expiration(
            # default record expiration
            default: :timer.seconds(60),

            # how often cleanup should occur
            interval: :timer.seconds(30),

            # whether to enable lazy checking
            lazy: true
          ),

          # complex limit
          limit: limit(
            size: 500,
            policy: Cachex.Policy.LRW,
            reclaim: 0.5,
            options: []
          ),

          ...
        ]
      end

  > See [Cachex.start_link/1][cachex_start_link] for more information.

  ## Telemetry events

  This adapter emits the recommended Telemetry events.
  See the "Telemetry events" section in `Nebulex.Cache`
  for more information.

  ## Distributed caching topologies

  In the same way we use the distributed adapters and the multilevel one to
  create distributed topologies, we can also do the same but instead of using
  the built-in local adapter using Cachex.

  For example, let's define a multi-level cache (near cache topology), where
  the L1 is a local cache using Cachex and the L2 is a partitioned cache.

      defmodule MyApp.NearCache do
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
            adapter: Nebulex.Adapters.Partitioned,
            primary_storage_adapter: Nebulex.Adapters.Cachex
        end
      end

  And the configuration may look like:

      config :my_app, MyApp.NearCache,
        model: :inclusive,
        levels: [
          {MyApp.NearCache.L1, [limit: 100_000]},
          {MyApp.NearCache.L2, primary: [limit: 1_000_000]}
        ]

  > **NOTE:** You could also use [NebulexRedisAdapter][nbx_redis_adapter] for
    L2, it would be matter of changing the adapter for the L2 and the
    configuration to set up Redis adapter.

  [nbx_redis_adapter]: https://github.com/cabol/nebulex_redis_adapter

  See [Nebulex examples](https://github.com/cabol/nebulex_examples). You will
  find examples for all different topologies, even using other adapters like
  Redis; for all examples you can just replace `Nebulex.Adapters.Local` by
  `Nebulex.Adapters.Cachex`.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Entry
  @behaviour Nebulex.Adapter.Queryable
  @behaviour Nebulex.Adapter.Persistence
  @behaviour Nebulex.Adapter.Stats

  # Inherit default transaction implementation
  use Nebulex.Adapter.Transaction

  import Nebulex.Adapter
  import Nebulex.Helpers

  alias Cachex.{Options, Query}
  alias Nebulex.Entry

  @compile {:inline, to_ttl: 1}

  ## Nebulex.Adapter

  @impl true
  defmacro __before_compile__(_), do: :ok

  @impl true
  def init(opts) do
    name =
      normalize_module_name([
        opts[:name] || Keyword.fetch!(opts, :cache),
        Cachex
      ])

    adapter_meta = %{
      name: name,
      telemetry: Keyword.fetch!(opts, :telemetry),
      telemetry_prefix: Keyword.fetch!(opts, :telemetry_prefix),
      stats: Options.get(opts, :stats, &is_boolean/1, false)
    }

    child_spec =
      opts
      |> Keyword.put(:name, name)
      |> Keyword.put(:stats, adapter_meta.stats)
      |> Cachex.child_spec()

    {:ok, child_spec, adapter_meta}
  end

  ## Nebulex.Adapter.Entry

  @impl true
  defspan get(adapter_meta, key, _opts) do
    Cachex.get!(adapter_meta.name, key)
  end

  @impl true
  defspan get_all(adapter_meta, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if value = Cachex.get!(adapter_meta.name, key) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  @impl true
  defspan put(adapter_meta, key, value, ttl, on_write, _opts) do
    do_put(adapter_meta.name, key, value, ttl, on_write)
  end

  defp do_put(name, key, value, ttl, :put) do
    Cachex.put!(name, key, value, ttl: to_ttl(ttl))
  end

  defp do_put(name, key, value, ttl, :replace) do
    Cachex.update!(name, key, value, ttl: to_ttl(ttl))
  end

  defp do_put(name, key, value, ttl, :put_new) do
    # FIXME: This is a workaround since Cachex does not support a direct action
    #        for put_new. Fix it if a better solution comes up.
    if Cachex.get!(name, key) do
      false
    else
      Cachex.put!(name, key, value, ttl: to_ttl(ttl))
    end
  end

  @impl true
  defspan put_all(adapter_meta, entries, ttl, on_write, _opts) do
    do_put_all(adapter_meta.name, entries, ttl, on_write)
  end

  defp do_put_all(name, entries, ttl, on_write) when is_map(entries) do
    do_put_all(name, :maps.to_list(entries), ttl, on_write)
  end

  defp do_put_all(name, entries, ttl, :put) when is_list(entries) do
    Cachex.put_many!(name, entries, ttl: to_ttl(ttl))
  end

  defp do_put_all(name, entries, ttl, :put_new) when is_list(entries) do
    {keys, _} = Enum.unzip(entries)

    # FIXME: This is a workaround since Cachex does not support a direct action
    #        for put_new. Fix it if a better solution comes up.
    Cachex.transaction!(name, keys, fn worker ->
      if Enum.any?(keys, &(worker |> Cachex.exists?(&1) |> elem(1))) do
        false
      else
        Cachex.put_many!(worker, entries, ttl: to_ttl(ttl))
      end
    end)
  end

  @impl true
  defspan delete(adapter_meta, key, _opts) do
    true = Cachex.del!(adapter_meta.name, key)
    :ok
  end

  @impl true
  defspan take(adapter_meta, key, _opts) do
    Cachex.take!(adapter_meta.name, key)
  end

  @impl true
  defspan has_key?(adapter_meta, key) do
    {:ok, bool} = Cachex.exists?(adapter_meta.name, key)
    bool
  end

  @impl true
  defspan ttl(adapter_meta, key) do
    cond do
      # Key does exist and has a TTL associated with it
      ttl = Cachex.ttl!(adapter_meta.name, key) ->
        ttl

      # Key does exist and hasn't a TTL associated with it
      Cachex.get!(adapter_meta.name, key) ->
        :infinity

      # Key does not exist
      true ->
        nil
    end
  end

  @impl true
  defspan expire(adapter_meta, key, ttl) do
    Cachex.expire!(adapter_meta.name, key, to_ttl(ttl))
  end

  @impl true
  defspan touch(adapter_meta, key) do
    Cachex.touch!(adapter_meta.name, key)
  end

  @impl true
  defspan update_counter(adapter_meta, key, amount, ttl, default, _opts) do
    do_update_counter(adapter_meta.name, key, amount, ttl, default)
  end

  defp do_update_counter(name, key, amount, :infinity, default) do
    Cachex.incr!(name, key, amount, initial: default)
  end

  defp do_update_counter(name, key, incr, ttl, default) do
    # FIXME: This is a workaround since Cachex does not support `:ttl` here.
    #        Fix it if a better solution comes up.
    Cachex.transaction!(name, [key], fn worker ->
      counter = Cachex.incr!(worker, key, incr, initial: default)
      if ttl = to_ttl(ttl), do: Cachex.expire!(worker, key, ttl)
      counter
    end)
  end

  ## Nebulex.Adapter.Queryable

  @impl true
  defspan execute(adapter_meta, operation, query, _opts) do
    do_execute(adapter_meta.name, operation, query)
  end

  defp do_execute(name, :count_all, nil) do
    Cachex.size!(name)
  end

  defp do_execute(name, :delete_all, nil) do
    Cachex.clear!(name)
  end

  defp do_execute(name, :delete_all, :expired) do
    Cachex.purge!(name)
  end

  defp do_execute(name, :all, query) do
    name
    |> do_stream(query, [])
    |> Enum.to_list()
  end

  defp do_execute(_name, operation, query) do
    raise Nebulex.QueryError, message: "unsupported #{operation}", query: query
  end

  @impl true
  defspan stream(adapter_meta, query, opts) do
    do_stream(adapter_meta.name, query, opts)
  end

  defp do_stream(name, nil, opts) do
    do_stream(name, Query.create(true, :key), opts)
  end

  defp do_stream(name, query, opts) do
    query = maybe_return_entry(query, opts[:return])
    Cachex.stream!(name, query, batch_size: opts[:page_size] || 20)
  rescue
    e in Cachex.ExecutionError ->
      reraise Nebulex.QueryError, [message: e.message, query: query], __STACKTRACE__
  end

  defp maybe_return_entry([{pattern, conds, _ret}], :key) do
    [{pattern, conds, [:"$1"]}]
  end

  defp maybe_return_entry([{pattern, conds, _ret}], :value) do
    [{pattern, conds, [:"$4"]}]
  end

  defp maybe_return_entry([{pattern, conds, _ret}], {:key, :value}) do
    [{pattern, conds, [{{:"$1", :"$4"}}]}]
  end

  defp maybe_return_entry([{pattern, conds, _ret}], :entry) do
    [{pattern, conds, [%Entry{key: :"$1", value: :"$4", touched: :"$2", ttl: :"$3"}]}]
  end

  defp maybe_return_entry(query, _return), do: query

  ## Nebulex.Adapter.Persistence

  @impl true
  defspan dump(adapter_meta, path, opts) do
    case Cachex.dump(adapter_meta.name, path, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
    end
  end

  @impl true
  defspan load(adapter_meta, path, opts) do
    case Cachex.load(adapter_meta.name, path, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
    end
  end

  ## Nebulex.Adapter.Stats

  @impl true
  defspan stats(adapter_meta) do
    if adapter_meta.stats do
      {meta, stats} =
        adapter_meta.name
        |> Cachex.stats!()
        |> Map.pop(:meta, %{})

      %Nebulex.Stats{
        measurements: stats,
        metadata: meta
      }
    end
  end

  ## Private Functions

  defp to_ttl(:infinity), do: nil
  defp to_ttl(ttl), do: ttl
end
