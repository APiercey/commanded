defmodule Commanded.Application do
  @moduledoc """
  Defines a Commanded application.

  The application expects at least an `:otp_app` option to be specified. It
  should point to an OTP application that has the application configuration.

  For example, the application:

      defmodule MyApp.Application do
        use Commanded.Application, otp_app: :my_app

        router(MyApp.Router)
      end

  Could be configured with:

      # config/config.exs
      config :my_app, MyApp.Application
        event_store: [
          adapter: Commanded.EventStore.Adapters.EventStore,
          event_store: MyApp.EventStore
        ],
        pubsub: :local,
        registry: :local

  Alternatively, you can include the event store, pubsub, and registry config
  when defining the application:

      defmodule MyApp.Application do
        use Commanded.Application,
          otp_app: :my_app,
          event_store: [
            adapter: Commanded.EventStore.Adapters.EventStore,
            event_store: MyApp.EventStore
          ],
          pubsub: :local,
          registry: :local

        router(MyApp.Router)
      end

  """

  @type t :: module

  @doc false
  defmacro __using__(opts) do
    quote bind_quoted: [opts: opts] do
      @behaviour Commanded.Application

      {otp_app, config} = Commanded.Application.Supervisor.compile_config(__MODULE__, opts)

      event_store_adapter = Commanded.EventStore.adapter(__MODULE__, config)
      pubsub_adapter = Commanded.PubSub.pubsub_provider(__MODULE__, config)
      registry_adapter = Commanded.Registration.registry_provider(__MODULE__, config)

      @otp_app otp_app
      @config config
      @name Keyword.get(opts, :name, __MODULE__)

      use Commanded.Commands.CompositeRouter,
        application: __MODULE__

      defmodule EventStore do
        use Commanded.EventStore.Adapter,
          adapter: event_store_adapter
      end

      defmodule PubSub do
        use Commanded.PubSub.Adapter,
          adapter: pubsub_adapter
      end

      defmodule Registration do
        use Commanded.Registration.Adapter,
          adapter: registry_adapter
      end

      def config do
        {:ok, config} =
          Commanded.Application.Supervisor.runtime_config(__MODULE__, @otp_app, @config, [])

        config
      end

      def child_spec(opts) do
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, [opts]},
          type: :supervisor
        }
      end

      def start_link(opts \\ []) do
        Commanded.Application.Supervisor.start_link(
          __MODULE__,
          @otp_app,
          EventStore,
          PubSub,
          Registration,
          @config,
          opts
        )
      end

      def stop(pid, timeout \\ 5000) do
        Supervisor.stop(pid, :normal, timeout)
      end
    end
  end

  ## User callbacks

  @optional_callbacks init: 1

  @doc """
  A callback executed when the application starts.

  It must return `{:ok, keyword}` with the updated list of configuration.
  """
  @callback init(config :: Keyword.t()) :: {:ok, Keyword.t()}

  @doc """
  Returns the application configuration stored in the `:otp_app` environment.
  """
  @callback config() :: Keyword.t()

  @doc """
  Starts the application supervisor.

  Returns `{:ok, pid}` on sucess, `{:error, {:already_started, pid}}` if the
  application is already started, or `{:error, term}` in case anything else goes
  wrong.
  """
  @callback start_link(opts :: Keyword.t()) ::
              {:ok, pid}
              | {:error, {:already_started, pid}}
              | {:error, term}

  @doc """
  Shuts down the application.
  """
  @callback stop(pid, timeout) :: :ok

  @doc """
  Dispatch a registered command.
  """
  @callback dispatch(command :: struct, timeout_or_opts :: integer | :infinity | Keyword.t()) ::
              :ok
              | {:ok, execution_result :: Commanded.Commands.ExecutionResult.t()}
              | {:ok, aggregate_version :: non_neg_integer()}
              | {:error, :unregistered_command}
              | {:error, :consistency_timeout}
              | {:error, reason :: term}

  @doc false
  def event_store_adapter(application), do: Module.concat([application, EventStore])

  @doc false
  def pubsub_adapter(application), do: Module.concat([application, PubSub])

  @doc false
  def registry_adapter(application), do: Module.concat([application, Registration])
end
