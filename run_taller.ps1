# ==========================================================
#  TALLER DOCKER - eco-air-backend  (ejecucion automatizada)
#  Genera audit_session.log + carpeta evidencias\
# ==========================================================
$ErrorActionPreference = "Continue"
Set-Location $PSScriptRoot
$STUDENT_ID = "890275"
$IMAGE = "eco-air-backend:1.0.0"
$ev = Join-Path $PSScriptRoot "evidencias"
New-Item -ItemType Directory -Force -Path $ev | Out-Null
Get-ChildItem $ev -File | Remove-Item -Force
Remove-Item -Force -ErrorAction SilentlyContinue (Join-Path $PSScriptRoot "audit_session.log")
Start-Transcript -Path (Join-Path $PSScriptRoot "audit_session.log") | Out-Null

function Run([string]$cmd, [string]$file) {
    $ts = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $header = "[$ts] PS> $cmd"
    Write-Host ""
    Write-Host $header -ForegroundColor Cyan
    $tmp = Join-Path $env:TEMP "eco_cmd.cmd"
    Set-Content -Path $tmp -Value "@echo off`r`n$cmd 2>&1" -Encoding Ascii
    $lines = New-Object System.Collections.Generic.List[string]
    cmd /c $tmp | ForEach-Object { Write-Host $_; $lines.Add([string]$_) }
    $code = $LASTEXITCODE
    Write-Host "(exit code: $code)" -ForegroundColor DarkGray
    if ($file) {
        Add-Content -Path (Join-Path $ev $file) -Value $header -Encoding UTF8
        if ($lines.Count -gt 0) { Add-Content -Path (Join-Path $ev $file) -Value $lines -Encoding UTF8 }
        Add-Content -Path (Join-Path $ev $file) -Value "(exit code: $code)`r`n" -Encoding UTF8
    }
}

function Section([string]$t) {
    Write-Host ""
    Write-Host ("=" * 70) -ForegroundColor Yellow
    Write-Host "  $t" -ForegroundColor Yellow
    Write-Host ("=" * 70) -ForegroundColor Yellow
}

# Espera a que la app arranque. Devuelve segundos de arranque, -1 si murio, -2 si timeout
function Wait-Started([string]$name, [int]$timeout) {
    for ($i = 0; $i -lt $timeout; $i++) {
        $st = (docker inspect -f "{{.State.Status}}" $name 2>$null)
        $l = (docker logs $name 2>&1 | Out-String)
        if ($l -match "Started EcoAirApplication in ([\d\.]+) seconds") { return [double]$matches[1] }
        if ($st -ne "running" -and $i -gt 1) { return -1 }
        Start-Sleep -Seconds 1
    }
    return -2
}

Section "PASO 0 - Entorno"
Run "date /t & time /t" "00_entorno.txt"
Run "docker --version" "00_entorno.txt"
Write-Host "Esperando a que Docker Engine este listo..." -ForegroundColor Gray
for ($i = 0; $i -lt 90; $i++) { docker info *> $null; if ($LASTEXITCODE -eq 0) { break }; Start-Sleep 2 }
Run "docker info --format ""Server: {{.ServerVersion}} | OS: {{.OperatingSystem}} | Kernel: {{.KernelVersion}} | CPUs: {{.NCPU}} | RAM: {{.MemTotal}}""" "00_entorno.txt"
Run "docker rm -f eco_air_active eco_air_crash" ""

Section "RETO 1 - Construccion multietapa"
Run "docker build --build-arg STUDENT_ID=""$STUDENT_ID"" -t $IMAGE ." "01_build.txt"
Run "docker images $IMAGE" "01_build.txt"
Run "docker image inspect $IMAGE --format ""Labels: {{json .Config.Labels}} | User: {{.Config.User}} | Env: {{json .Config.Env}}""" "01_build.txt"

Section "RETO 2.1 - Historial de capas"
Run "docker history --human --format ""table {{.Size}}\t{{.CreatedBy}}"" $IMAGE" "02_1_history.txt"

Section "RETO 2.2 - Proceso del host"
Run "docker run -d --name eco_air_active -p 8080:8080 $IMAGE" "02_2_run_top.txt"
$t = Wait-Started "eco_air_active" 90
Write-Host "Arranque detectado: $t s" -ForegroundColor Green
Run "docker top eco_air_active -o pid,user,comm" "02_2_run_top.txt"
Run "docker exec eco_air_active id" "02_2_run_top.txt"
Run "curl.exe -s http://localhost:8080/api/health" "02_2_run_top.txt"

Section "RETO 2.3 - Inmutabilidad de runtime"
Run "docker exec eco_air_active touch /etc/crontab_fake" "02_3_touch.txt"
Run "docker exec eco_air_active ls -ld /etc /app" "02_3_touch.txt"

Section "RETO 2.4 - Artefactos de desarrollo"
Run "docker exec eco_air_active which mvn" "02_4_artefactos.txt"
Run "docker exec eco_air_active find / -name ""*.java"" 2>NUL" "02_4_artefactos.txt"
Run "docker exec eco_air_active ls -la /app" "02_4_artefactos.txt"

Section "IDENTIDAD"
Run "docker inspect --format=""{{.Id}}"" $IMAGE" "04_identidad.txt"
Run "docker exec eco_air_active env | findstr OPERATOR_ID" "04_identidad.txt"
Run "docker inspect --format=""{{.Id}}"" eco_air_active" "04_identidad.txt"

Section "RETO 3.1 - Colapso por memoria (48 MB)"
Run "docker run -d --name eco_air_crash -m 48m $IMAGE" "03_1_oom.txt"
Start-Sleep -Seconds 10
Run "docker inspect eco_air_crash --format=""Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}""" "03_1_oom.txt"
Run "docker inspect eco_air_crash --format=""Memory limit (bytes): {{.HostConfig.Memory}}""" "03_1_oom.txt"
Run "docker logs --tail 25 eco_air_crash" "03_1_oom.txt"

Section "RETO 3.2 - Calibracion del limite minimo"
$sizes = @(96, 128, 160, 192, 224, 256, 288, 320, 384, 448, 512)
$found = $null
$resumen = @()
foreach ($m in $sizes) {
    Write-Host ""
    Write-Host "----- Probando -m ${m}m -----" -ForegroundColor Magenta
    docker rm -f eco_air_active *> $null
    Run "docker run -d --name eco_air_active -p 8080:8080 -m ${m}m $IMAGE" "03_2_calibracion.txt"
    $secs = Wait-Started "eco_air_active" 45
    $state = (docker inspect eco_air_active --format "Status={{.State.Status}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}" 2>$null)
    if ($secs -gt 0) {
        Start-Sleep -Seconds 8
        $state = (docker inspect eco_air_active --format "Status={{.State.Status}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}" 2>$null)
    }
    $line = "${m}m | arranque=$secs s | $state"
    Write-Host $line -ForegroundColor Magenta
    Add-Content -Path (Join-Path $ev "03_2_calibracion.txt") -Value "RESULTADO: $line`r`n" -Encoding UTF8
    $resumen += $line
    if ($secs -gt 0 -and $secs -lt 15 -and $state -match "Status=running") {
        Run "docker logs --timestamps eco_air_active | findstr /C:""Started EcoAirApplication""" "03_2_calibracion.txt"
        Run "docker stats --no-stream eco_air_active" "03_2_calibracion.txt"
        $found = $m
        break
    } else {
        Run "docker logs --tail 5 eco_air_active" "03_2_calibracion.txt"
    }
}
Set-Content -Path (Join-Path $ev "03_2_resumen.txt") -Value $resumen -Encoding UTF8
Add-Content -Path (Join-Path $ev "03_2_resumen.txt") -Value "UMBRAL_MINIMO=${found}m" -Encoding UTF8

Section "CONSUMO FINAL CALIBRADO (${found}m)"
Start-Sleep -Seconds 10
Run "docker logs --timestamps eco_air_active | findstr /C:""Started EcoAirApplication""" "05_final.txt"
Run "docker stats --no-stream eco_air_active" "05_final.txt"
Start-Sleep -Seconds 5
Run "docker stats --no-stream eco_air_active" "05_final.txt"
Run "docker exec eco_air_active env | findstr OPERATOR_ID" "05_final.txt"
Run "docker inspect --format=""{{.Id}}"" $IMAGE" "05_final.txt"
Run "docker ps -a --filter name=eco_air" "05_final.txt"
Run "date /t & time /t" "05_final.txt"

Write-Host ""
Write-Host "UMBRAL MINIMO ENCONTRADO: ${found}m" -ForegroundColor Green
Set-Content -Path (Join-Path $ev "FIN.txt") -Value "OK $(Get-Date -Format s) umbral=${found}m" -Encoding UTF8
Stop-Transcript | Out-Null
Write-Host "TALLER TERMINADO. Puedes cerrar esta ventana." -ForegroundColor Green
