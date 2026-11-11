# Monitor de turnos

Revisa cada 5 minutos la disponibilidad de un club en ATC y manda un mensaje por Telegram
cuando se libera un turno nuevo dentro del rango de días y horarios configurado.

## Configuración

Todo se configura con **Settings → Secrets and variables → Actions → New repository secret**:

| Secret | Obligatorio | Ejemplo |
|---|---|---|
| `CLUB_ID` | sí | id numérico del club en ATC |
| `TELEGRAM_TOKEN` | sí | token de @BotFather |
| `TELEGRAM_CHAT_ID` | sí | ver abajo |
| `DIAS` | no | `Mon,Tue,Wed,Thu,Fri` (default) |
| `HORA_DESDE` / `HORA_HASTA` | no | `17:00` / `21:30` (default) |
| `DURACION_MIN` | no | `90` (default) |
| `SPORT_ID` | no | `7` = pádel (default) |

Para el `TELEGRAM_CHAT_ID`: mandale un mensaje al bot y abrí
`https://api.telegram.org/bot<TOKEN>/getUpdates`; es el número en `"chat":{"id": ...}`.

Después, en **Actions → Monitor → Run workflow** se puede correr a mano para probar.
