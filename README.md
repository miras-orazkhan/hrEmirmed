# hr.emirmed

API рекрутинговой системы. Ruby 3.3.8, Rails 8.1, PostgreSQL.

- [Техническое задание](docs/hr_emirmed_specification_v0_1.md)
- [Архитектура, схема БД, доступ и план](docs/architecture_and_database.md)
- [Шаблоны, заявки и кампании: API](docs/recruitment_planning_api.md)
- [Реестр кандидатов: API](docs/candidate_registry.md)
- [Рассмотрения кандидатов](docs/candidate_applications.md)
- [Импорт кандидатов](docs/candidate_imports.md)
- [Файлы резюме](docs/candidate_resumes.md)
- [Веб-интерфейс](docs/web_interface.md)
- [Визуальная система](DESIGN.md)

Реализованы вход/выход, пользователи, роли, оргструктура, юрлица, аудит,
шаблоны вакансий, заявки и кампании, реестр кандидатов, рассмотрения, JSON-импорт,
загрузка файлов резюме и веб-интерфейс рабочих потоков, включая администрирование
и справочник причин отказа. Импорт кандидатов и разрешение дублей в HTML пока
отсутствуют — эти операции идут через API. Интеграции с внешними каналами,
автоматические тесты кандидатов и оформление найма ещё не реализованы.

## Локальный запуск

```sh
bundle install
docker compose up -d db
bin/rails db:prepare
bin/rails db:seed
bin/rails server
```

После запуска откройте `http://localhost:3000/session/new` для входа в веб-интерфейс.

Compose публикует PostgreSQL только на `127.0.0.1:5433`.
Настройки можно переопределить через `DB_HOST`, `DB_PORT`, `DB_USERNAME`, `DB_PASSWORD`
или `DATABASE_URL`. Production использует отдельные базы primary/cache/queue/cable,
пароль берётся из окружения, встроенного production-пароля нет.

`db:seed` создаёт роли `admin`, `hr_manager`, `recruiter`, `department_manager` и первого пользователя. Для локального запуска задайте в корневом `.env` переменные `ADMIN_LOGIN`, `ADMIN_NAME`, `ADMIN_PASSWORD` (минимум 12 символов), `ADMIN_BRANCH`, `ADMIN_DEPARTMENT`, затем выполните `bin/rails db:seed`. `.env` загружается только в development; уже заданные переменные окружения имеют приоритет. Не сохраняйте `.env` или пароль в Git. Повторный seed не меняет пароль существующего пользователя.

## API v1

Все запросы, кроме создания сессии и `/up`, требуют `Authorization: Bearer <token>`.

| Метод | Путь | Назначение |
| --- | --- | --- |
| POST | `/api/v1/session` | Вход: `{"session":{"login":"...","password":"..."}}` |
| DELETE | `/api/v1/session` | Выход из текущей сессии |
| GET | `/api/v1/me` | Профиль и разрешения |
| GET, POST | `/api/v1/branches` | Список / создание филиала |
| GET, PATCH | `/api/v1/branches/:id` | Просмотр / изменение филиала |
| GET, POST | `/api/v1/departments` | Список / создание подразделения |
| GET, PATCH | `/api/v1/departments/:id` | Просмотр / изменение подразделения |
| GET, POST | `/api/v1/legal_entities` | Список / создание юрлица |
| GET, PATCH | `/api/v1/legal_entities/:id` | Просмотр / изменение юрлица |
| GET, POST | `/api/v1/users` | Список / создание сотрудника |
| GET, PATCH | `/api/v1/users/:id` | Просмотр / изменение, включая деактивацию |
| GET, POST | `/api/v1/roles` | Список / создание роли |
| PATCH | `/api/v1/roles/:id` | Изменение роли |
| GET | `/api/v1/audit_events` | Журнал изменений |

Тело записи оборачивается в имя сущности: `branch`, `department`, `legal_entity`, `user`, `role`.
Поля пользователя: `login`, `full_name`, `password`, `password_confirmation`,
`active`, `branch_id`, `role_id`, `department_ids`.
Права ролей возвращаются в `available_permissions` списка ролей.

Списки принимают `limit=1..200` (по умолчанию 50) и `cursor=<id>`.
Заголовок `X-Next-Cursor` содержит курсор следующей страницы, если она есть.
Аудит сортируется от новых событий к старым; остальные списки — по возрастанию ID.
Списки пользователей и подразделений дополнительно принимают `branch_id`.
Список ролей обёрнут в объект `roles`, остальные списки — массивы.

Ошибки: 400 неверные параметры, 401 нет действующей сессии, 403 запрещено,
404 объект отсутствует/вне области чтения, 409 конфликт уникальности,
422 некорректные данные, 429 превышен лимит входа.
Пароли и digest сессии в ответы не включаются. Токен возвращается только при входе.

## Проверки

```sh
bin/rails test
RUBOCOP_CACHE_ROOT=tmp/rubocop bin/rubocop
bin/brakeman --no-pager
RAILS_ENV=test bin/rails runner script/benchmark_database.rb
```

Бенчмарк использует выделенную тестовую БД, создаёт синтетические записи и откатывает
транзакцию. Не запускать одновременно с тестами. Его результаты и ограничения
описаны в документе архитектуры.
