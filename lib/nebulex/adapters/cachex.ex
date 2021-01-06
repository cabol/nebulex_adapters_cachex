defmodule Nebulex.Adapters.Cachex do
  @moduledoc """
  Nebulex adapter for [Cachex][Cachex].

  [Cachex]: http://hexdocs.pm/cachex/Cachex.html

  This adapter allows to use Cachex (a widely used and powerful cache in Elixir)
  via Nebulex, which means, you can use Nebulex as usual taking advantage of all
  its benefits (e.g.: cache abstraction layer, distributed caching topologies,
  declarative caching annotations, and so on), and at the same time using Cachex
  as cache backend.

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
    configuration for set up Redis adapter.

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

    stats =
      if opts[:stats_counter] do
        true
      else
        Options.get(opts, :stats, &is_boolean/1, false)
      end

    child_spec =
      opts
      |> Keyword.put(:name, name)
      |> Keyword.put(:stats, stats)
      |> Cachex.child_spec()

    {:ok, child_spec, %{name: name, stats: stats}}
  end

  ## Nebulex.Adapter.Entry

  @impl true
  def get(%{name: name}, key, _opts) do
    Cachex.get!(name, key)
  end

  @impl true
  def get_all(%{name: name}, keys, _opts) do
    Enum.reduce(keys, %{}, fn key, acc ->
      if value = Cachex.get!(name, key) do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  @impl true
  def put(%{name: name}, key, value, ttl, :put, _opts) do
    Cachex.put!(name, key, value, ttl: to_ttl(ttl))
  end

  def put(%{name: name}, key, value, ttl, :replace, _opts) do
    Cachex.update!(name, key, value, ttl: to_ttl(ttl))
  end

  def put(%{name: name}, key, value, ttl, :put_new, _opts) do
    # FIXME: This is a workaround since Cachex does not support a direct action
    #        for put_new. Fix it if a better solution comes up.
    if Cachex.get!(name, key) do
      false
    else
      Cachex.put!(name, key, value, ttl: to_ttl(ttl))
    end
  end

  @impl true
  def put_all(adapter_meta, entries, ttl, on_write, opts) when is_map(entries) do
    put_all(adapter_meta, :maps.to_list(entries), ttl, on_write, opts)
  end

  def put_all(%{name: name}, entries, ttl, :put, _opts) when is_list(entries) do
    Cachex.put_many!(name, entries, ttl: to_ttl(ttl))
  end

  def put_all(%{name: name}, entries, ttl, :put_new, _opts) when is_list(entries) do
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
  def delete(%{name: name}, key, _opts) do
    true = Cachex.del!(name, key)
    :ok
  end

  @impl true
  def take(%{name: name}, key, _opts) do
    Cachex.take!(name, key)
  end

  @impl true
  def has_key?(%{name: name}, key) do
    {:ok, bool} = Cachex.exists?(name, key)
    bool
  end

  @impl true
  def ttl(%{name: name}, key) do
    cond do
      # Key does exist and has a TTL associated with it
      ttl = Cachex.ttl!(name, key) ->
        ttl

      # Key does exist and hasn't a TTL associated with it
      Cachex.get!(name, key) ->
        :infinity

      # Key does not exist
      true ->
        nil
    end
  end

  @impl true
  def expire(%{name: name}, key, ttl) do
    Cachex.expire!(name, key, to_ttl(ttl))
  end

  @impl true
  def touch(%{name: name}, key) do
    Cachex.touch!(name, key)
  end

  @impl true
  def update_counter(%{name: name}, key, amount, :infinity, default, _opts) do
    Cachex.incr!(name, key, amount, initial: default)
  end

  def update_counter(%{name: name}, key, incr, ttl, default, _opts) do
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
  def execute(%{name: name}, :count_all, nil, _opts) do
    Cachex.size!(name)
  end

  def execute(%{name: name}, :delete_all, nil, _opts) do
    Cachex.clear!(name)
  end

  def execute(%{name: name}, :delete_all, :expired, _opts) do
    Cachex.purge!(name)
  end

  def execute(adapter_meta, :all, query, opts) do
    adapter_meta
    |> stream(query, opts)
    |> Enum.to_list()
  end

  def execute(_adapter_meta, operation, query, _opts) do
    raise Nebulex.QueryError, message: "unsupported #{operation}", query: query
  end

  @impl true
  def stream(adapter_meta, nil, opts) do
    stream(adapter_meta, Query.create(true, :key), opts)
  end

  def stream(%{name: name}, query, opts) do
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
  def dump(%{name: name}, path, opts) do
    case Cachex.dump(name, path, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
    end
  end

  @impl true
  def load(%{name: name}, path, opts) do
    case Cachex.load(name, path, opts) do
      {:ok, true} -> :ok
      {:error, _} = error -> error
    end
  end

  ## Nebulex.Adapter.Stats

  @impl true
  def stats(%{name: name, stats: stats}) do
    if stats do
      # IO.puts "#=> Stats: #{inspect(Cachex.stats(name))}"

      {meta, stats} =
        name
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
