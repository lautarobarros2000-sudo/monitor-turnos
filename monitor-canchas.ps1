# Monitor de turnos libres en ATC (atcsports.io / alquilatucancha)
# Avisa por Telegram (y notificacion de Windows si corre en la PC)
# cuando aparece un turno NUEVO dentro de los dias/horarios configurados.
#
# Configuracion por variables de entorno (en GitHub: Secrets del repo):
#   CLUB_ID          id del club en ATC (obligatorio)
#   SPORT_ID         deporte (default 7 = padel)
#   DIAS             dias a vigilar, ej "Mon,Tue,Wed,Thu,Fri" (default L-V)
#   HORA_DESDE       inicio minimo del turno, ej "17:00"
#   HORA_HASTA       inicio maximo del turno, ej "21:30"
#   DURACION_MIN     duracion minima en minutos (default 90)
#   TELEGRAM_TOKEN / TELEGRAM_CHAT_ID
# Corriendo local, se pueden poner en config.local.json (misma carpeta, ignorado por git):
#   {"CLUB_ID":"...","TELEGRAM_TOKEN":"...","TELEGRAM_CHAT_ID":"...","HORA_DESDE":"17:00"}

$ErrorActionPreference = "Stop"
$ConfigFile = Join-Path $PSScriptRoot "config.local.json"
$cfgLocal = $null
if (Test-Path $ConfigFile) { $cfgLocal = Get-Content $ConfigFile -Raw | ConvertFrom-Json }
function Cfg($nombre, $default) {
    $v = [Environment]::GetEnvironmentVariable($nombre)
    if (-not $v -and $cfgLocal -and $cfgLocal.$nombre) { $v = "$($cfgLocal.$nombre)" }
    if (-not $v) { $v = $default }
    return "$v".Trim()
}

$ClubId      = Cfg "CLUB_ID" ""
$SportId     = Cfg "SPORT_ID" "7"
$Dias        = @((Cfg "DIAS" "Mon,Tue,Wed,Thu,Fri").Split(",") | ForEach-Object { $_.Trim().Substring(0,3) } | Where-Object { $_ })
$HoraDesde   = Cfg "HORA_DESDE" "17:00"
$HoraHasta   = Cfg "HORA_HASTA" "21:30"
$DuracionMin = [int](Cfg "DURACION_MIN" "90")
$DiasAdelante = 6
$TelegramToken  = Cfg "TELEGRAM_TOKEN" ""
$TelegramChatId = Cfg "TELEGRAM_CHAT_ID" ""
if (-not $ClubId) { throw "Falta CLUB_ID (Secret del repo o config.local.json)" }

$EnWindows = ($PSVersionTable.PSEdition -eq "Desktop") -or $IsWindows
$ToastWindows = $EnWindows
# Hora de Argentina (en GitHub Actions el reloj esta en UTC)
$tzId = if ($EnWindows) { "Argentina Standard Time" } else { "America/Argentina/Buenos_Aires" }
$ahoraAR = [TimeZoneInfo]::ConvertTimeBySystemTimeZoneId([DateTime]::UtcNow, $tzId)

$StateFile = Join-Path $PSScriptRoot "estado.json"
$LogFile   = Join-Path $PSScriptRoot "monitor.log"
function Log($msg) { "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  $msg" | Out-File -Append -Encoding utf8 $LogFile }

function Notificar($titulo, $texto, $url) {
    if ($ToastWindows) { try {
        [Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] | Out-Null
        [Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] | Out-Null
        $esc = { param($s) [System.Security.SecurityElement]::Escape($s) }
        $xml = New-Object Windows.Data.Xml.Dom.XmlDocument
        $xml.LoadXml("<toast activationType='protocol' launch='$url' scenario='reminder'><visual><binding template='ToastGeneric'><text>$(& $esc $titulo)</text><text>$(& $esc $texto)</text></binding></visual><actions><action content='Abrir ATC' activationType='protocol' arguments='$url'/></actions></toast>")
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show([Windows.UI.Notifications.ToastNotification]::new($xml))
    } catch { Log "Error toast: $_" } }
    if ($TelegramToken -and $TelegramChatId) {
        try {
            Invoke-RestMethod -Method Post "https://api.telegram.org/bot$TelegramToken/sendMessage" `
                -Body @{ chat_id = $TelegramChatId; text = "$titulo`n$texto`n$url" } | Out-Null
        } catch { Log "Error Telegram: $_" }
    }
}

$previos = @()
if (Test-Path $StateFile) { $previos = @(Get-Content $StateFile -Raw | ConvertFrom-Json) }

$actuales = @()
$clubNombre = "el club"; $clubUrl = "https://atcsports.io"
$hoy = $ahoraAR.Date
for ($i = 0; $i -le $DiasAdelante; $i++) {
    $fecha = $hoy.AddDays($i)
    if ($Dias.Count -and ($Dias -notcontains $fecha.DayOfWeek.ToString().Substring(0,3))) { continue }
    $f = $fecha.ToString("yyyy-MM-dd")
    try {
        $data = Invoke-RestMethod -UseBasicParsing "https://alquilatucancha.com/api/v3/availability/sportclubs/${ClubId}?date=$f"
    } catch { Log "Error consultando $f"; continue }
    if ($data.name) { $clubNombre = $data.name }
    if ($data.permalink) { $clubUrl = "https://atcsports.io/venues/$($data.permalink)" }
    foreach ($c in $data.available_courts) {
        if ($c.sport_ids -notcontains $SportId) { continue }
        foreach ($s in $c.available_slots) {
            $hora = $s.start.Substring(11,5)
            if ($s.start.Substring(0,10) -ne $f) { continue }
            if ($i -eq 0 -and $hora -le $ahoraAR.ToString("HH:mm")) { continue }  # ya empezo
            if ($hora -lt $HoraDesde -or $hora -gt $HoraHasta) { continue }
            if ($s.duration -lt $DuracionMin) { continue }
            $actuales += "$f $hora | $($c.name) | $($s.duration) min | `$$([int]($s.price.cents/100))"
        }
    }
}
$actuales = @($actuales | Sort-Object -Unique)

$nuevos = @($actuales | Where-Object { $previos -notcontains $_ })
if ($nuevos.Count) {
    Log "Turnos nuevos: $($nuevos.Count)"
    $grupos = $nuevos | Group-Object { $_.Split('|')[0].Trim() } | ForEach-Object {
        $d = [datetime]::ParseExact($_.Name, "yyyy-MM-dd HH:mm", $null)
        "$($d.ToString('ddd dd/MM HH:mm', [Globalization.CultureInfo]'es-AR')) - $($_.Count) cancha(s)"
    }
    $resumen = ($grupos | Select-Object -First 8) -join "`n"
    if (@($grupos).Count -gt 8) { $resumen += "`n(+ otros horarios)" }
    Notificar "Se libero cancha en $clubNombre ($($nuevos.Count))" $resumen $clubUrl
} else {
    Log "Sin novedades ($($actuales.Count) turnos dentro del filtro)"
}
ConvertTo-Json @($actuales) | Out-File -Encoding utf8 $StateFile
