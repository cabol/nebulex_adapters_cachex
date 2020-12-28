defmodule Nebulex.Adapters.Cachex do
  @moduledoc """
  Nebulex adapter for Cachex.
  """

  # Provide Cache Implementation
  @behaviour Nebulex.Adapter
  @behaviour Nebulex.Adapter.Queryable

  import Nebulex.Helpers

  alias Cachex.Query

  @compile {:inline, to_ttl: 1}

  ## Adapter

  @impl true
  defmacro __before_compile__(_), do: :ok

  @impl true
  def init(opts) do
    name =
      normalize_module_name([
        opts[:name] || Keyword.fetch!(opts, :cache),
        Cachex
      ])

    child_spec =
      opts
      |> Keyword.put(:name, name)
      |> Cachex.child_spec()

    {:ok, child_spec, %{name: name}}
  end

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
  def incr(%{name: name}, key, incr, :infinity, opts) do
    Cachex.incr!(name, key, incr, initial: opts[:default] || 0)
  end

  def incr(%{name: name}, key, incr, ttl, opts) do
    # FIXME: This is a workaround since Cachex does not support `:ttl` here.
    #        Fix it if a better solution comes up.
    Cachex.transaction!(name, [key], fn worker ->
      counter = Cachex.incr!(worker, key, incr, initial: opts[:default] || 0)
      if ttl = to_ttl(ttl), do: Cachex.expire!(worker, key, ttl)
      counter
    end)
  end

  @impl true
  def size(%{name: name}) do
    Cachex.size!(name)
  end

  @impl true
  def flush(%{name: name}) do
    size = Cachex.size!(name)
    true = Cachex.reset!(name)
    size
  end

  ## Queryable

  @impl true
  def all(adapter_meta, query, opts) do
    adapter_meta
    |> stream(query, opts)
    |> Enum.to_list()
  end

  @impl true
  def stream(adapter_meta, nil, opts) do
    stream(adapter_meta, Query.create(true, :key), opts)
  end

  def stream(%{name: name}, query, opts) do
    Cachex.stream!(name, query, batch_size: opts[:page_size] || 100)
  rescue
    e in Cachex.ExecutionError ->
      reraise Nebulex.QueryError, [message: e.message, query: query], __STACKTRACE__
  end

  ## Private Functions

  defp to_ttl(:infinity), do: nil
  defp to_ttl(ttl), do: ttl
end
