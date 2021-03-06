defmodule Commanded.JsonSerializerApplication do
  alias Commanded.EventStore.Adapters.InMemory
  alias Commanded.Serialization.JsonSerializer

  use Commanded.Application,
    otp_app: :commanded,
    event_store: [
      adapter: InMemory,
      serializer: JsonSerializer
      # encoding_options: %{escape: :unicode}
    ]
end
