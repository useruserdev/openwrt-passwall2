# Установка исправленного passwall2 (автообновление подписки)

Этот форк исправляет автообновление подписки:

1. **Циклический режим (Loop Mode) переживает рестарты.** Время последнего обновления хранится в конфиге (`last_update`), а не в памяти процесса. Раньше любой перезапуск сервиса (смена настроек, события сети, ручное обновление) сбрасывал счётчик, и при частых рестартах автообновление не срабатывало никогда.
2. **Фолбэк на прямое соединение.** Если подписка не скачалась через туннель (например, VPN-нода мертва), запрос повторяется напрямую: IP сервера подписки временно (~5 минут) добавляется в набор `psw2_direct` и обходит ядро. VPN при этом **не отключается** — весь остальной трафик продолжает идти через туннель.

Изменены только 3 файла:

| В репозитории | На роутере |
|---|---|
| `luci-app-passwall2/root/usr/share/passwall2/tasks.sh` | `/usr/share/passwall2/tasks.sh` |
| `luci-app-passwall2/root/usr/share/passwall2/subscribe.lua` | `/usr/share/passwall2/subscribe.lua` |
| `luci-app-passwall2/luasrc/passwall2/api.lua` | `/usr/lib/lua/luci/passwall2/api.lua` |

---

## Способ 1 — быстрый: скопировать 3 файла (без пересборки)

Подходит, если passwall2 уже установлен. Выполнить с компьютера (замените `192.168.1.1` на адрес роутера):

```sh
git clone https://github.com/useruserdev/openwrt-passwall2.git
cd openwrt-passwall2

scp luci-app-passwall2/root/usr/share/passwall2/tasks.sh      root@192.168.1.1:/usr/share/passwall2/tasks.sh
scp luci-app-passwall2/root/usr/share/passwall2/subscribe.lua root@192.168.1.1:/usr/share/passwall2/subscribe.lua
scp luci-app-passwall2/luasrc/passwall2/api.lua               root@192.168.1.1:/usr/lib/lua/luci/passwall2/api.lua
```

> Если `scp` ругается на протокол (на роутере dropbear), добавьте флаг `-O`.

Затем на роутере (по SSH):

```sh
rm -f /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null
/etc/init.d/passwall2 restart
```

### Проверка

```sh
# должен работать фоновый процесс цикла обновления
pgrep -f tasks.sh

# после первого автообновления у подписки появится метка времени
uci show passwall2 | grep last_update
```

Лог обновлений: LuCI → PassWall 2 → в логе будут строки `Start subscribing...`.

**Важно:** при обновлении пакета `luci-app-passwall2` из штатного репозитория эти файлы перезапишутся — нужно будет скопировать их снова (или использовать способ 2).

---

## Способ 2 — собрать пакет из форка (OpenWrt SDK / buildroot)

В `feeds.conf.default` (или `feeds.conf`) замените источник passwall2 на форк:

```
src-git passwall2 https://github.com/useruserdev/openwrt-passwall2.git;main
```

Затем:

```sh
./scripts/feeds update passwall2
./scripts/feeds install -a -p passwall2
make package/luci-app-passwall2/compile V=s
```

Готовый `.ipk`/`.apk` появится в `bin/packages/.../passwall2/` — установить на роутере:

```sh
opkg install luci-app-passwall2*.ipk
```

В форке также активен апстримный workflow «Auto compile with openwrt sdk» — собранные пакеты можно брать из GitHub Actions → Artifacts.

---

## Настройка автообновления

LuCI → **PassWall 2 → Node Subscribe** → выбрать подписку:

- **Auto Update Mode** — `Loop Mode` (обновление каждые N часов) или конкретный день/время.
- **Update Interval (hour)** — интервал для Loop Mode.
- **Subscribe URL Access Method** — оставьте `Auto`: сначала попытка через туннель, при неудаче — напрямую. Режим `Proxy` фолбэка не делает (строго через туннель).
- **Update Once on Boot** — обновлять при загрузке роутера (опционально).

Нюансы поведения:

- Если интервал уже истёк (например, роутер был выключен), обновление произойдёт в течение ~10–20 минут после запуска сервиса.
- Интервал отсчитывается от последней **попытки** обновления (удачной или нет).
- Loop Mode работает, только когда сервис passwall2 включён и работает в режиме прокси.

---

## Синхронизация форка с апстримом

Форк ежедневно подтягивает изменения из [Openwrt-Passwall/openwrt-passwall2](https://github.com/Openwrt-Passwall/openwrt-passwall2) (workflow `Sync fork with upstream`, мерж в `main`). Если апстрим изменит те же 3 файла и возникнет конфликт, workflow упадёт — тогда мерж нужно сделать вручную.
