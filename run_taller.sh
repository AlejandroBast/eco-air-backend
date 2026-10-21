#!/usr/bin/env bash
# ==========================================================
#  TALLER DOCKER - eco-air-backend (Linux)
#  Uso:  ./run_taller.sh
#  Genera audit_session.log + carpeta evidencias/
# ==========================================================
cd "$(dirname "$0")"

# Se graba a si mismo con `script` para dejar audit_session.log
if [ -z "$TALLER_GRABANDO" ]; then
  rm -f audit_session.log
  if command -v script >/dev/null 2>&1; then
    TALLER_GRABANDO=1 script -q -e -c "bash '$0'" audit_session.log
  else
    TALLER_GRABANDO=1 bash "$0" 2>&1 | tee audit_session.log
  fi
  exit
fi

STUDENT_ID="890275"
IMAGE="eco-air-backend:1.0.0"
EV="evidencias"
mkdir -p "$EV" && rm -f "$EV"/*

run() {   # run "comando" archivo
  local cmd="$1" file="$2"
  local header="[$(date '+%Y-%m-%d %H:%M:%S')] \$ $cmd"
  echo; echo -e "\e[36m$header\e[0m"
  local out; out=$(bash -c "$cmd" 2>&1); local code=$?
  [ -n "$out" ] && echo "$out"
  echo "(exit code: $code)"
  if [ -n "$file" ]; then
    { echo "$header"; [ -n "$out" ] && echo "$out"; echo "(exit code: $code)"; echo; } >> "$EV/$file"
  fi
}

section() { echo; printf '%.0s=' {1..70}; echo; echo "  $1"; printf '%.0s=' {1..70}; echo; }

# Segundos de arranque; -1 si murio, -2 si timeout
wait_started() {
  local name="$1" timeout="$2" i st secs
  for ((i=0; i<timeout; i++)); do
    st=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
    secs=$(docker logs "$name" 2>&1 | grep -oP 'Started EcoAirApplication in \K[\d.]+' | head -1)
    [ -n "$secs" ] && { echo "$secs"; return; }
    [ "$st" != "running" ] && [ $i -gt 1 ] && { echo -1; return; }
    sleep 1
  done
  echo -2
}

section "PASO 0 - Entorno"
run "date" "00_entorno.txt"
run "docker --version" "00_entorno.txt"
run "docker info --format 'Server: {{.ServerVersion}} | OS: {{.OperatingSystem}} | Kernel: {{.KernelVersion}} | CPUs: {{.NCPU}} | RAM: {{.MemTotal}} | Cgroup: {{.CgroupVersion}}'" "00_entorno.txt"
docker rm -f eco_air_active eco_air_crash >/dev/null 2>&1

section "RETO 1 - Construccion multietapa"
run "docker build --build-arg STUDENT_ID=\"$STUDENT_ID\" -t $IMAGE ." "01_build.txt"
run "docker images $IMAGE" "01_build.txt"
run "docker image inspect $IMAGE --format 'Labels: {{json .Config.Labels}} | User: {{.Config.User}} | Env: {{json .Config.Env}}'" "01_build.txt"

section "RETO 2.1 - Historial de capas"
run "docker history --human --format 'table {{.Size}}\t{{.CreatedBy}}' $IMAGE" "02_1_history.txt"

section "RETO 2.2 - Proceso del host"
run "docker run -d --name eco_air_active -p 8080:8080 $IMAGE" "02_2_run_top.txt"
t=$(wait_started eco_air_active 90); echo "Arranque detectado: $t s"
run "docker top eco_air_active -o pid,user,comm" "02_2_run_top.txt"
run "docker exec eco_air_active id" "02_2_run_top.txt"
run "curl -s http://localhost:8080/api/health" "02_2_run_top.txt"

section "RETO 2.3 - Inmutabilidad de runtime"
run "docker exec eco_air_active touch /etc/crontab_fake" "02_3_touch.txt"
run "docker exec eco_air_active ls -ld /etc /app" "02_3_touch.txt"

section "RETO 2.4 - Artefactos de desarrollo"
run "docker exec eco_air_active which mvn" "02_4_artefactos.txt"
run "docker exec eco_air_active find / -name '*.java' 2>/dev/null" "02_4_artefactos.txt"
run "docker exec eco_air_active ls -la /app" "02_4_artefactos.txt"

section "IDENTIDAD"
run "docker inspect --format='{{.Id}}' $IMAGE" "04_identidad.txt"
run "docker exec eco_air_active env | grep OPERATOR_ID" "04_identidad.txt"
run "docker inspect --format='{{.Id}}' eco_air_active" "04_identidad.txt"

section "RETO 3.1 - Colapso por memoria (48 MB)"
run "docker run -d --name eco_air_crash -m 48m $IMAGE" "03_1_oom.txt"
sleep 10
run "docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'" "03_1_oom.txt"
run "docker inspect eco_air_crash --format='Memory limit (bytes): {{.HostConfig.Memory}}'" "03_1_oom.txt"
run "docker logs --tail 25 eco_air_crash" "03_1_oom.txt"

section "RETO 3.2 - Calibracion del limite minimo"
found=""
: > "$EV/03_2_resumen.txt"
for m in 96 128 160 192 224 256 288 320 384 448 512; do
  echo; echo "----- Probando -m ${m}m -----"
  docker rm -f eco_air_active >/dev/null 2>&1
  run "docker run -d --name eco_air_active -p 8080:8080 -m ${m}m $IMAGE" "03_2_calibracion.txt"
  secs=$(wait_started eco_air_active 45)
  if awk "BEGIN{exit !($secs>0)}"; then sleep 8; fi
  state=$(docker inspect eco_air_active --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}' 2>/dev/null)
  line="${m}m | arranque=${secs} s | $state"
  echo "$line"
  echo "RESULTADO: $line" >> "$EV/03_2_calibracion.txt"
  echo "$line" >> "$EV/03_2_resumen.txt"
  if awk "BEGIN{exit !($secs>0 && $secs<15)}" && [[ "$state" == *"Status=running"* ]]; then
    run "docker logs --timestamps eco_air_active | grep 'Started EcoAirApplication'" "03_2_calibracion.txt"
    run "docker stats --no-stream eco_air_active" "03_2_calibracion.txt"
    found=$m; break
  else
    run "docker logs --tail 5 eco_air_active" "03_2_calibracion.txt"
  fi
done
echo "UMBRAL_MINIMO=${found}m" >> "$EV/03_2_resumen.txt"

section "CONSUMO FINAL CALIBRADO (${found}m)"
sleep 10
run "docker logs --timestamps eco_air_active | grep 'Started EcoAirApplication'" "05_final.txt"
run "docker stats --no-stream eco_air_active" "05_final.txt"
sleep 5
run "docker stats --no-stream eco_air_active" "05_final.txt"
run "docker exec eco_air_active env | grep OPERATOR_ID" "05_final.txt"
run "docker inspect --format='{{.Id}}' $IMAGE" "05_final.txt"
run "docker ps -a --filter name=eco_air" "05_final.txt"
run "date" "05_final.txt"

echo; echo "UMBRAL MINIMO ENCONTRADO: ${found}m"
echo "OK $(date -Is) umbral=${found}m" > "$EV/FIN.txt"
echo "TALLER TERMINADO."
