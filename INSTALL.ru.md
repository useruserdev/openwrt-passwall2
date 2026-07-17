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

## Xiaomi AX3200 / Redmi AX6S: защита от отката на сток

Заводской загрузчик Xiaomi — двухсистемный, со счётчиком неудачных загрузок. OpenWrt эти счётчики не сбрасывает, поэтому на новых ревизиях загрузчика (2022+) примерно **на 6-й перезагрузке роутер сам откатывается на стоковую прошивку**.

### Перед прошивкой (по telnet на стоке)

```sh
nvram set ssh_en=1
nvram set uart_en=1
nvram set boot_wait=on
nvram set flag_boot_success=1
nvram set flag_try_sys1_failed=0
nvram set flag_try_sys2_failed=0
nvram commit
```

Затем прошивка:

```sh
cd /tmp
wget http://<ip-компьютера>:8000/factory.bin
mtd -r write factory.bin firmware
```

### После установки OpenWrt (обязательно, один раз)

```sh
fw_setenv boot_fw1 "run boot_rd_img;bootm"
fw_setenv flag_try_sys1_failed 8
fw_setenv flag_try_sys2_failed 8
fw_setenv flag_boot_rootfs 0
fw_setenv flag_boot_success 1
fw_setenv flag_last_success 1
```

Проверка: `fw_printenv | grep flag_try` — должно показать `flag_try_sys1_failed=8`.

Альтернатива (страховка на каждый запуск) — добавить в `/etc/rc.local` до строки `exit 0`:

```sh
fw_setenv flag_try_sys1_failed 0
fw_setenv flag_try_sys2_failed 0
```

---

## AX3200: не хватает места под новые ядра (sing-box/xray)

Свежие бинарники выросли: sing-box ~43 МБ, xray-core ~29 МБ, а на `/overlay` у AX6S всего ~24 МБ — через `opkg install` они **не влезают**. Решение: собрать образ через **ImageBuilder** — пакеты из образа попадают в сжатый squashfs (xray ужимается примерно до 11 МБ), а не в overlay. Ставьте только **один** core (для passwall2 достаточно xray-core, sing-box не обязателен).

1. Скачайте ImageBuilder для платформы **mediatek/mt7622** с [downloads.openwrt.org](https://downloads.openwrt.org/) (свою версию OpenWrt), распакуйте.

2. В `repositories.conf` добавьте прошивочные фиды passwall (архитектура AX6S — `aarch64_cortex-a53`, путь подставьте под свою версию OpenWrt, пример для 24.10):

   ```
   src/gz passwall_packages https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-24.10/aarch64_cortex-a53/passwall_packages
   src/gz passwall2 https://master.dl.sourceforge.net/project/openwrt-passwall-build/releases/packages-24.10/aarch64_cortex-a53/passwall2
   ```

3. Впеките исправленные файлы этого форка в образ через `FILES`:

   ```sh
   mkdir -p files/usr/share/passwall2 files/usr/lib/lua/luci/passwall2
   cp <форк>/luci-app-passwall2/root/usr/share/passwall2/tasks.sh      files/usr/share/passwall2/
   cp <форк>/luci-app-passwall2/root/usr/share/passwall2/subscribe.lua files/usr/share/passwall2/
   cp <форк>/luci-app-passwall2/luasrc/passwall2/api.lua               files/usr/lib/lua/luci/passwall2/
   ```

4. Соберите образ (только нужное, без лишних протоколов):

   ```sh
   make image PROFILE=xiaomi_redmi-router-ax6s \
     PACKAGES="luci luci-app-passwall2 xray-core" \
     FILES=files
   ```

5. Прошейте полученный **sysupgrade**-образ из LuCI (System → Backup/Flash Firmware) или `sysupgrade -n`.

Настройки passwall2 перед прошивкой сохраните (Backup), после — восстановите. И не забудьте про защиту от отката (раздел выше).

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
