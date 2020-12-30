## Benchmarks

defmodule Cache do
  @moduledoc false
  use Nebulex.Cache,
    otp_app: :nebulex,
    adapter: Nebulex.Adapters.Cachex
end

benchmarks = %{
  "get" => fn input ->
    Cache.get(input)
  end,
  "get_all" => fn input ->
    Cache.get_all([input, "foo", "bar"])
  end,
  "put" => fn input ->
    Cache.put(input, input)
  end,
  "put_new" => fn input ->
    Cache.put_new(input, input)
  end,
  "replace" => fn input ->
    Cache.replace(input, input)
  end,
  "put_all" => fn input ->
    Cache.put_all([{input, input}, {"foo", "bar"}])
  end,
  "delete" => fn input ->
    Cache.delete(input)
  end,
  "take" => fn input ->
    Cache.take(input)
  end,
  "has_key?" => fn input ->
    Cache.has_key?(input)
  end,
  "size" => fn _input ->
    Cache.size()
  end,
  "ttl" => fn input ->
    Cache.ttl(input)
  end,
  "expire" => fn input ->
    Cache.expire(input, 1)
  end,
  "incr" => fn _input ->
    Cache.incr(:counter, 1)
  end,
  "update" => fn input ->
    Cache.update(input, 1, &Kernel.+(&1, 1))
  end,
  "all" => fn _input ->
    Cache.all()
  end
}

# start local cache
{:ok, local} = Cache.start_link()

Benchee.run(
  benchmarks,
  inputs: %{"rand" => 100_000},
  before_each: fn n -> :rand.uniform(n) end,
  formatters: [
    {Benchee.Formatters.Console, comparison: false, extended_statistics: true},
    {Benchee.Formatters.HTML, extended_statistics: true, auto_open: false}
  ],
  print: [
    fast_warning: false
  ]
)

# stop cache
if Process.alive?(local), do: Supervisor.stop(local)
