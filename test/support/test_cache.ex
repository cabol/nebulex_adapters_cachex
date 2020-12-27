defmodule NebulexCachexAdapter.TestCache do
  @moduledoc false

  defmodule Common do
    @moduledoc false

    defmacro __using__(_opts) do
      quote do
        def get_and_update_fun(nil), do: {nil, 1}
        def get_and_update_fun(current) when is_integer(current), do: {current, current * 2}

        def get_and_update_bad_fun(_), do: :other
      end
    end
  end

  defmodule Local do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex_cachex_adapter,
      adapter: NebulexCachexAdapter

    use NebulexCachexAdapter.TestCache.Common
  end

  defmodule Partitioned do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex_cachex_adapter,
      adapter: Nebulex.Adapters.Partitioned,
      primary_storage_adapter: NebulexCachexAdapter

    use NebulexCachexAdapter.TestCache.Common
  end

  defmodule Replicated do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex_cachex_adapter,
      adapter: Nebulex.Adapters.Replicated,
      primary_storage_adapter: NebulexCachexAdapter

    use NebulexCachexAdapter.TestCache.Common
  end

  defmodule Multilevel do
    @moduledoc false
    use Nebulex.Cache,
      otp_app: :nebulex_cachex_adapter,
      adapter: Nebulex.Adapters.Multilevel

    defmodule L1 do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex_cachex_adapter,
        adapter: NebulexCachexAdapter
    end

    defmodule L2 do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex_cachex_adapter,
        adapter: Nebulex.Adapters.Replicated,
        primary_storage_adapter: NebulexCachexAdapter
    end

    defmodule L3 do
      @moduledoc false
      use Nebulex.Cache,
        otp_app: :nebulex_cachex_adapter,
        adapter: Nebulex.Adapters.Partitioned,
        primary_storage_adapter: NebulexCachexAdapter
    end
  end
end
