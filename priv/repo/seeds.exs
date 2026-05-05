alias FeedService.Repo
alias FeedService.Feed.FeedItem

user1 = "00000000-0000-0000-0000-000000000001"
user2 = "00000000-0000-0000-0000-000000000002"
proj1 = "00000000-0000-0000-0000-000000000010"
proj2 = "00000000-0000-0000-0000-000000000011"

items = [
  %{
    source_type: "project",
    source_id: proj1,
    project_id: proj1,
    actor_id: user1,
    actor_name: "Alice",
    actor_avatar_url: nil,
    verb: "created",
    label: "Мониторинг птиц в городской среде",
    short_description: "Помогаем учёным собирать данные о городских птицах",
    description: nil,
    media_ids: [],
    payload: %{},
    event_id: "seed:project:#{proj1}:created",
    occurred_at: DateTime.add(DateTime.utc_now(), -3600, :second)
  },
  %{
    source_type: "post",
    source_id: Ecto.UUID.generate(),
    project_id: proj1,
    actor_id: user1,
    actor_name: "Alice",
    actor_avatar_url: nil,
    verb: "created",
    label: "Первые результаты наблюдений",
    short_description: "За две недели зафиксировано 14 видов",
    description: "Подробный отчёт по районам города...",
    media_ids: [],
    payload: %{},
    event_id: "seed:post:first_results:created",
    occurred_at: DateTime.add(DateTime.utc_now(), -1800, :second)
  },
  %{
    source_type: "task",
    source_id: Ecto.UUID.generate(),
    project_id: proj1,
    actor_id: user1,
    actor_name: "Alice",
    actor_avatar_url: nil,
    verb: "created",
    label: "Сфотографируйте птиц в парке",
    short_description: "Нужны фото городских птиц в утреннее время",
    description: nil,
    media_ids: [],
    payload: %{},
    event_id: "seed:task:birds_photo:created",
    occurred_at: DateTime.add(DateTime.utc_now(), -900, :second)
  },
  %{
    source_type: "project",
    source_id: proj2,
    project_id: proj2,
    actor_id: user2,
    actor_name: "Bob",
    actor_avatar_url: nil,
    verb: "created",
    label: "Качество воздуха: краудсорсинг данных",
    short_description: "Собираем измерения с личных датчиков",
    description: nil,
    media_ids: [],
    payload: %{},
    event_id: "seed:project:#{proj2}:created",
    occurred_at: DateTime.add(DateTime.utc_now(), -300, :second)
  },
  %{
    source_type: "response",
    source_id: Ecto.UUID.generate(),
    project_id: proj1,
    actor_id: user2,
    actor_name: "Bob",
    actor_avatar_url: nil,
    verb: "answered",
    label: nil,
    short_description: nil,
    description: nil,
    media_ids: [],
    payload: %{"task_label" => "Сфотографируйте птиц в парке"},
    event_id: "seed:response:birds_photo:user2",
    occurred_at: DateTime.utc_now()
  }
]

Enum.each(items, fn attrs ->
  %FeedItem{}
  |> FeedItem.changeset(attrs)
  |> Repo.insert!(on_conflict: :nothing, conflict_target: :event_id)
  |> then(fn item -> IO.puts("inserted: #{item.source_type} — #{item.label || "(no label)"}") end)
end)

IO.puts("\nSeeded #{length(items)} feed items.")
IO.puts("project_ids: #{proj1}, #{proj2}")
IO.puts("Try: GET /api/v1/feed/projects/#{proj1}")
