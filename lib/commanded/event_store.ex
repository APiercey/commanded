defmodule Commanded.EventStore do
  @moduledoc """
  Defines the behaviour to be implemented by an event store adapter to be used by Commanded.
  """

  alias Commanded.Application
  alias Commanded.EventStore.{EventData, RecordedEvent, SnapshotData}

  @type application :: module
  @type opts :: Keyword.t()
  @type event_store :: {module, opts}
  @type stream_uuid :: String.t()
  @type start_from :: :origin | :current | integer
  @type expected_version :: :any_version | :no_stream | :stream_exists | non_neg_integer
  @type subscription_name :: String.t()
  @type subscription :: any
  @type subscriber :: pid
  @type source_uuid :: String.t()
  @type error :: term

  @doc """
  Return a child spec defining all processes required by the event store.
  """
  @callback child_spec(module, opts) :: [:supervisor.child_spec()]

  @doc """
  Append one or more events to a stream atomically.
  """
  @callback append_to_stream(
              event_store,
              stream_uuid,
              expected_version,
              events :: list(EventData.t())
            ) ::
              :ok
              | {:error, :wrong_expected_version}
              | {:error, error}

  @doc """
  Streams events from the given stream, in the order in which they were
  originally written.
  """
  @callback stream_forward(
              event_store,
              stream_uuid,
              start_version :: non_neg_integer,
              read_batch_size :: non_neg_integer
            ) ::
              Enumerable.t()
              | {:error, :stream_not_found}
              | {:error, error}

  @doc """
  Create a transient subscription to a single event stream.

  The event store will publish any events appended to the given stream to the
  `subscriber` process as an `{:events, events}` message.

  The subscriber does not need to acknowledge receipt of the events.
  """
  @callback subscribe(event_store, stream_uuid | :all) :: :ok | {:error, error}

  @doc """
  Create a persistent subscription to an event stream.

  To subscribe to all events appended to any stream use `:all` as the stream
  when subscribing.

  The event store will remember the subscribers last acknowledged event.
  Restarting the named subscription will resume from the next event following
  the last seen.

  Once subscribed, the subscriber process should be sent a
  `{:subscribed, subscription}` message to allow it to defer initialisation
  until the subscription has started.

  The subscriber process will be sent all events persisted to any stream. It
  will receive a `{:events, events}` message for each batch of events persisted
  for a single aggregate.

  The subscriber must ack each received, and successfully processed event, using
  `c:Commanded.EventStore.ack_event/3`.

  ## Examples

  Subscribe to all streams:

      {:ok, subscription} =
        Commanded.EventStore.subscribe_to(MyApp, :all, "Example", self(), :current)

  Subscribe to a single stream:

      {:ok, subscription} =
        Commanded.EventStore.subscribe_to(MyApp, "stream1", "Example", self(), :origin)

  """
  @callback subscribe_to(
              event_store,
              stream_uuid | :all,
              subscription_name,
              subscriber,
              start_from
            ) ::
              {:ok, subscription}
              | {:error, :subscription_already_exists}
              | {:error, error}

  @doc """
  Acknowledge receipt and successful processing of the given event received from
  a subscription to an event stream.
  """
  @callback ack_event(event_store, pid, RecordedEvent.t()) :: :ok

  @doc """
  Unsubscribe an existing subscriber from event notifications.

  This will not delete the subscription.

  ## Example

      :ok = Commanded.EventStore.unsubscribe(MyApp, subscription)

  """
  @callback unsubscribe(event_store, subscription) :: :ok

  @doc """
  Delete an existing subscription.

  ## Example

      :ok = Commanded.EventStore.delete_subscription(MyApp, :all, "Example")

  """
  @callback delete_subscription(event_store, stream_uuid | :all, subscription_name) ::
              :ok | {:error, :subscription_not_found} | {:error, error}

  @doc """
  Read a snapshot, if available, for a given source.
  """
  @callback read_snapshot(event_store, source_uuid) ::
              {:ok, SnapshotData.t()} | {:error, :snapshot_not_found}

  @doc """
  Record a snapshot of the data and metadata for a given source
  """
  @callback record_snapshot(event_store, SnapshotData.t()) :: :ok | {:error, error}

  @doc """
  Delete a previously recorded snapshot for a given source
  """
  @callback delete_snapshot(event_store, source_uuid) :: :ok | {:error, error}

  @doc false
  def append_to_stream(application, stream_uuid, expected_version, events) do
    Application.event_store_adapter(application).append_to_stream(
      stream_uuid,
      expected_version,
      events
    )
  end

  @doc false
  def stream_forward(application, stream_uuid, start_version \\ 0, read_batch_size \\ 1_000) do
    Application.event_store_adapter(application).stream_forward(
      stream_uuid,
      start_version,
      read_batch_size
    )
  end

  @doc false
  def subscribe(application, stream_uuid) do
    Application.event_store_adapter(application).subscribe(stream_uuid)
  end

  @doc false
  def subscribe_to(application, stream_uuid, subscription_name, subscriber, start_from) do
    Application.event_store_adapter(application).subscribe_to(
      stream_uuid,
      subscription_name,
      subscriber,
      start_from
    )
  end

  @doc false
  def ack_event(application, subscription, event) do
    Application.event_store_adapter(application).ack_event(subscription, event)
  end

  @doc false
  def unsubscribe(application, subscription) do
    Application.event_store_adapter(application).unsubscribe(subscription)
  end

  @doc false
  def delete_subscription(application, subscribe_to, handler_name) do
    Application.event_store_adapter(application).delete_subscription(subscribe_to, handler_name)
  end

  @doc false
  def read_snapshot(application, source_uuid) do
    Application.event_store_adapter(application).read_snapshot(source_uuid)
  end

  @doc false
  def record_snapshot(application, snapshot) do
    Application.event_store_adapter(application).record_snapshot(snapshot)
  end

  @doc false
  def delete_snapshot(application, source_uuid) do
    Application.event_store_adapter(application).delete_snapshot(source_uuid)
  end

  @doc """
  Get the configured event store adapter for the given application.
  """
  def adapter(_application, config) do
    event_store = Keyword.get(config, :event_store)

    unless event_store do
      raise ArgumentError, "missing :event_store option on use Commanded.Application"
    end

    {adapter, _config} = Keyword.pop(event_store, :adapter)

    unless Code.ensure_compiled?(adapter) do
      raise ArgumentError,
            "event store adapter #{inspect(adapter)} was not compiled, " <>
              "ensure it is correct and it is included as a project dependency"
    end

    adapter
  end
end
