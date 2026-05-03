defmodule FeedService.Events.Handlers.ProfileHandler do
  @moduledoc """
  Обрабатывает событие `profile_service.profile.changed`.

  ВНИМАНИЕ: на 2026-05-03 producer-а у profile_service НЕТ
  (см. memory: eggs_event_contracts). Этот handler — заглушка
  под будущую интеграцию. Broadway-pipeline на топик
  `profile_service.profile.changed` подписан НЕ будет, пока
  событие не появится в системе.
  """

  alias FeedService.Events.Schema

  @kinds [:profile_changed]

  def handles?(%Schema{kind: kind}), do: kind in @kinds

  # TODO(upstream) profile_service:
  # ЧТО НУЖНО ДОБАВИТЬ в profile_service:
  #   1. В `profile_service/src/main.py` создать AIOKafkaProducer
  #      аналогично project_service (он уже это делает).
  #   2. В `infrastructure/` добавить класс KafkaProducerClient
  #      с методом `send_profile_changed(profile)`:
  #        topic = "profile_service.profile.changed"
  #        payload = {
  #          "type": "profile.changed",
  #          "user_id": str(profile.id),
  #          "name": profile.name,
  #          "avatar_url": profile.avatar_url,
  #          "timestamp": datetime.now(timezone.utc).isoformat(),
  #        }
  #   3. Вызывать producer в `services/profile_service.py`
  #      на update-методах профиля.
  #
  # КОГДА ПОЯВИТСЯ — обновить `Schema.decode_topic/2`:
  #   defp decode_topic("profile_service.profile.changed", p), do:
  #     build(:profile_changed, p, &profile_attrs/1)
  # И заменить тело `handle/1` ниже на:
  #   Feed.upsert_profile(%{
  #     user_id: attrs.user_id,
  #     name: attrs.name,
  #     avatar_url: attrs.avatar_url
  #   })
  #
  # До этого момента наполнение `profiles_cache` — лениво, через
  # REST-клиент `ProfileClient` (этап 7) при cold-miss обогащения
  # ленты.
  def handle(%Schema{kind: :profile_changed}), do: :ok
end
