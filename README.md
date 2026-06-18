# Feed Service

- Потребляет события из Kafka и проецирует их в таблицу `feed_items`
- Отдаёт глобальную и проектную ленту с курсорной пагинацией
- Обогащает элементы ленты именами и аватарами авторов: кэш профилей
  (`profiles_cache`) обновляется из Kafka-событий `user-events`, с
  REST-fallback в profile_service при промахе кэша

## Запуск

- Локально: `mix setup && mix phx.server` (порт 4000)
- В Docker: сервис `feed-service` в `infra_faberge/docker-compose.yaml`

## API

- `GET /api/v1/health` - healthcheck
- `GET /api/v1/feed/global` - глобальная лента
- `GET /api/v1/feed/projects/:project_id` - лента проекта

## Kafka

Подписан на топики: `project.created/updated`, `post.created/updated/deleted`,
`task.created/updated/deleted`, `response_service.response.add/delete`,
`user-events`

## TODO

### s2s-auth
`lib/feed_service/clients/project_client.ex`

feed_service ходит в project_service с фиктивным заголовком
`x-user-id: 00000000-...`. Внутри Docker-сети любой сервис может выдать
себя за другого. Нужна S2S-аутентификация по `X-Service-Token` (похожее
уже реализовано в media_service)

### member-events
`lib/feed_service/events/handlers/project_handler.ex`

Таблица `memberships` не заполняется: project_service не публикует события
вступления/выхода участников, поэтому фильтрация ленты по членству неполная
