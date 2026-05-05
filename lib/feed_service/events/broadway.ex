defmodule FeedService.Events.Broadway do
  @moduledoc """
  Kafka consumer pipeline. Returns `:ignore` from `start_link/1` when
  no brokers are configured, so REST keeps working without RedPanda.
  """

  use Broadway

  require Logger

  alias Broadway.Message
  alias FeedService.Events.Schema

  alias FeedService.Events.Handlers.{
    ProjectHandler,
    ProfileHandler,
    ResponseHandler
  }

  @handlers [ProjectHandler, ResponseHandler, ProfileHandler]

  # TODO(upstream) profile_service: add "profile_service.profile.changed"
  # once the producer exists in profile_service.
  @topics [
    "project.created",
    "project.updated",
    "post.created",
    "post.updated",
    "post.deleted",
    "task.created",
    "task.updated",
    "task.deleted",
    "response_service.response.add",
    "response_service.response.delete"
  ]

  def start_link(_opts) do
    config = Application.fetch_env!(:feed_service, :kafka)

    case config[:brokers] do
      [] ->
        Logger.info("Broadway: no Kafka brokers configured, pipeline disabled")
        :ignore

      brokers when is_list(brokers) ->
        Broadway.start_link(__MODULE__,
          name: __MODULE__,
          producer: [
            module:
              {BroadwayKafka.Producer,
               [
                 hosts: brokers,
                 group_id: config[:group_id],
                 topics: @topics,
                 offset_reset_policy: :latest
               ]},
            concurrency: 1
          ],
          processors: [default: [concurrency: 4]]
        )
    end
  end

  @impl true
  def handle_message(_processor_name, %Message{data: body, metadata: meta} = msg, _ctx) do
    topic = meta[:topic] || ""

    case Schema.decode(topic, body) do
      {:ok, event} ->
        case dispatch(event) do
          :ok ->
            msg

          {:error, reason} ->
            Logger.error("handler error: topic=#{topic} reason=#{inspect(reason)}")
            Message.failed(msg, "handler_error: #{inspect(reason)}")
        end

      {:error, reason} ->
        # Skip poison messages (ack without retry) — otherwise one bad
        # payload blocks the partition forever.
        Logger.warning("decode failed: topic=#{topic} reason=#{inspect(reason)}")
        msg
    end
  end

  defp dispatch(event) do
    Enum.find_value(@handlers, {:error, :no_handler}, fn handler ->
      if handler.handles?(event), do: handler.handle(event)
    end)
  end
end
