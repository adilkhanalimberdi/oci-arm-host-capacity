# Инструкция: бесплатный ARM-сервер в Oracle Cloud (регион Osaka)

Краткая инструкция под конкретную конфигурацию: Japan Central (Osaka), `VM.Standard.A1.Flex`,
2 OCPU / 12 GB RAM, Ubuntu (aarch64), boot volume 100 GB, публичный IPv4.

## Как это работает

Кнопка «Create» в консоли Oracle отправляет один запрос `LaunchInstance`. Если свободного железа нет,
приходит `Out of capacity`. Скрипт `index.php` отправляет **тот же самый запрос** через API,
а cron (или `loop.sh`) повторяет его раз в минуту. Как только Oracle освобождает мощности,
очередная попытка проходит, и инстанс создаётся. После этого скрипт видит, что инстанс уже есть,
и больше ничего не создаёт.

Скрипт должен работать **постоянно** (часы, дни, иногда недели), поэтому нужен компьютер,
который всё время включён (см. раздел «Где запускать»).

## Важно знать заранее

- **Домашний регион сменить нельзя.** В Osaka только один availability domain (AD-1), так что
  перебирать AD бесполезно: скрипт просто долбит AD-1.
- **Самый надёжный способ — перейти на Pay As You Go (PAYG)**: Billing → Upgrade.
  Always Free ресурсы остаются бесплатными, но у PAYG-аккаунтов приоритет на ARM, и
  «Out of capacity» почти пропадает. Сразу поставьте Budget alert (например, $1), чтобы случайно
  ничего не оплатить. Бонус: Oracle не отбирает простаивающие инстансы у PAYG-аккаунтов
  (у Free Tier может отобрать, если CPU < 20% в течение 7 дней).
- Бесплатные **200 GB** — это общий лимит на все диски (boot + block volumes). Если планируете
  ещё и маленькую AMD-машину (см. ниже), оставьте на неё ~50 GB.

## Шаг 1. API-ключ

1. Консоль Oracle → иконка профиля → **User settings** (My profile) → **API keys** → **Add API key**.
2. «Generate API key pair» → **Download private key** (файл `*.pem`) → **Add**.
3. Скопируйте показанный текст конфигурации — там будут `user`, `fingerprint`, `tenancy`, `region`.

## Шаг 2. SSH-ключ

Это ключ, по которому вы будете заходить на сервер. Если его нет:

```bash
ssh-keygen -t ed25519 -f ~/.ssh/oci
cat ~/.ssh/oci.pub   # эту строку нужно вставить в OCI_SSH_PUBLIC_KEY
```

## Шаг 3. subnetId и imageId

1. В консоли: Compute → Instances → Create instance, выберите всё как обычно
   (Ubuntu, A1.Flex 2/12, диск 100 GB, публичный IP — Yes).
2. Откройте DevTools браузера (F12) → вкладка **Network**.
3. Нажмите **Create**, получите «Out of capacity».
4. Найдите красный запрос `instances` → правый клик → **Copy as cURL**.
5. В скопированном тексте найдите `"subnetId"` и `"imageId"` — это `OCI_SUBNET_ID` и `OCI_IMAGE_ID`.

Если subnet-а ещё нет — в мастере создания инстанса выберите «Create new virtual cloud network»
(публичная подсеть), это можно сделать и без успешного создания инстанса, либо создайте VCN
заранее через Networking → Virtual cloud networks → Start VCN Wizard.

## Шаг 4. Установка и `.env`

Нужны PHP 8.x и composer (Ubuntu/WSL: `sudo apt install php-cli php-curl php-xml composer git`).

```bash
git clone https://github.com/adilkhanalimberdi/oci-arm-host-capacity.git
cd oci-arm-host-capacity
composer install
cp .env.example .env
nano .env
```

Заполните `.env` (значения в угловых скобках — ваши):

```bash
OCI_REGION=ap-osaka-1
OCI_USER_ID=<ocid1.user...>
OCI_TENANCY_ID=<ocid1.tenancy...>
OCI_KEY_FINGERPRINT=<aa:bb:...>
OCI_PRIVATE_KEY_FILENAME="/home/<you>/.oci/<ключ>.pem"   # абсолютный путь!
OCI_SUBNET_ID=<ocid1.subnet.oc1.ap-osaka-1...>
OCI_IMAGE_ID=<ocid1.image.oc1.ap-osaka-1...>

OCI_OCPUS=2
OCI_MEMORY_IN_GBS=12
OCI_SHAPE=VM.Standard.A1.Flex
OCI_MAX_INSTANCES=1

OCI_SSH_PUBLIC_KEY="ssh-ed25519 AAAA... you@pc"   # одной строкой, без переносов

OCI_AVAILABILITY_DOMAIN=
CACHE_AVAILABILITY_DOMAINS=1
OCI_BOOT_VOLUME_SIZE_IN_GBS=100
OCI_BOOT_VOLUME_ID=
OCI_ASSIGN_PUBLIC_IP=1

TOO_MANY_REQUESTS_TIME_WAIT=600

# необязательно: уведомление в Telegram при успехе
TELEGRAM_BOT_API_KEY=
TELEGRAM_USER_ID=
```

**Никогда не коммитьте `.env` и `.pem`** — они уже в `.gitignore`.

Проверка:

```bash
php index.php
```

Ожидаемый ответ — `Out of host capacity` / `Out of capacity`. Это значит, что всё настроено
правильно. Если ошибка другая (`NotAuthenticated`, `InvalidParameter`, `NotAuthorizedOrNotFound`) —
проверьте ключ, fingerprint и OCID-ы.

## Шаг 5. Где запускать

| Вариант | Плюсы / минусы |
|---|---|
| **Бесплатная AMD-машина `VM.Standard.E2.1.Micro`** в том же аккаунте | Работает 24/7 бесплатно. Её тоже иногда нет в наличии, но обычно получить проще. |
| **Свой Linux/macOS/WSL-компьютер** | Просто, но компьютер должен быть включён. |
| GitHub Actions по расписанию | **Не делайте** — нарушает правила GitHub, могут заблокировать аккаунт. |

### Вариант A — cron (Linux / macOS / сервер)

```bash
crontab -e
```

Добавьте строку (пути — абсолютные):

```bash
* * * * * cd /home/<you>/oci-arm-host-capacity && /usr/bin/php index.php >> oci.log 2>&1
```

Смотреть лог: `tail -f oci.log`.

### Вариант B — `loop.sh` (WSL на Windows, или если cron неудобен)

```bash
tmux new -s oci          # чтобы скрипт не умер при закрытии терминала
./loop.sh                # или: ./loop.sh .env 60
# отсоединиться: Ctrl+B, затем D;  вернуться: tmux attach -t oci
```

Скрипт сам остановится, когда инстанс будет создан.

## Шаг 6. После успеха

1. Удалите строку из cron (`crontab -e`) или убедитесь, что `loop.sh` остановился.
2. В консоли откройте инстанс, скопируйте Public IP.
3. Заходите (для Ubuntu пользователь — `ubuntu`, не `opc`):

```bash
ssh -i ~/.ssh/oci ubuntu@<public-ip>
```

4. Чтобы открыть порты (например 80/443): добавьте Ingress rule в Security List подсети
   **и** откройте порт в `iptables` на самой машине (в образах Oracle он закрыт по умолчанию).
