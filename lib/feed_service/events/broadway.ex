defmodule FeedService.Events.Broadway do
  @moduledoc """
  Pipeline потребления событий из RedPanda/Kafka.

  Под капотом — Broadway с adapter-ом BroadwayKafka.Producer (тот в свою
  очередь использует Erlang-клиент `:brod`). Pipeline:

      Kafka topic → Producer → Processor (handle_message/3) → ack

  Маршрутизация: `Schema.decode/2` превращает сырое сообщение в struct,
  затем перебираются handlers — первый, кто отвечает `handles?(event)`,
  получает событие на обработку.

  Если `KAFKA_BROKERS` пустой (по умолчанию в dev) — `start_link/1`
  возвращает `:ignore`, и supervisor спокойно стартует остальное
  приложение без подписки на Kafka. Это позволяет работать с REST
  даже когда RedPanda не поднята.
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

  # Топики, на которые мы подписаны. Имена соответствуют тому, что
  # реально публикуют upstream-сервисы сегодня (см. memory:
  # eggs_event_contracts).
  #
  # TODO(upstream) profile_service: добавить
  # "profile_service.profile.changed" в список, когда producer появится
  # в profile_service. См. ProfileHandler.
  @topics [
    "project.created",
    "project.updated",
    "post.create",
    "post.update",
    "post.delete",
    "task.create",
    "task.delete",
    "response_service.response.add",
    "response_service.response.delete"
  ]

  def start_link(_opts) do
    config = Application.fetch_env!(:feed_service, :kafka)

    case config[:brokers] do
      [] ->
        Logger.info("Broadway: KAFKA_BROKERS пуст, pipeline не стартует")
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
                 # `:latest` — стартуем с конца лога; новый consumer
                 # не пытается переварить весь history. Для backfill
                 # переключим на `:earliest`.
                 offset_reset_policy: :latest
               ]},
            concurrency: 1
          ],
          processors: [
            default: [concurrency: 4]
          ],
          partition_by: &partition/1
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
            Logger.error(
              "feed_service handler error: topic=#{topic} reason=#{inspect(reason)}"
            )

            Message.failed(msg, "handler_error: #{inspect(reason)}")
        end

      {:error, reason} ->
        # Нечитаемое сообщение НЕ помечаем как failed — иначе вечный
        # retry заблокирует партицию. Логируем и подтверждаем (skip).
        Logger.warning(
          "feed_service decode failed: topic=#{topic} reason=#{inspect(reason)}"
        )

        msg
    end
  end

  defp dispatch(event) do
    Enum.find_value(@handlers, {:error, :no_handler}, fn handler ->
      if handler.handles?(event), do: handler.handle(event)
    end)
  end

  # Сохраняем порядок per-entity внутри одного процессора.
  # project_service использует UUID сущности как Kafka-key
  # (см. project_service/kafka_producer.py: `key=str(post.post_id)`).
  defp partition(%Message{metadata: %{key: key}}) when is_binary(key) and key != "" do
    :erlang.phash2(key)
  end

  defp partition(_msg), do: 0
end
