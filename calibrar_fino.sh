#!/usr/bin/env bash
# Afina el umbral minimo de memoria por debajo de 96m
cd "$(dirname "$0")"
IMAGE="eco-air-backend:1.0.0"
OUT="evidencias/03_3_calibracion_fina.txt"
: > "$OUT"
{
echo "==================== RETO 3.2b - Calibracion fina (64m-88m) ===================="
found=96
for m in 64 72 80 88; do
  docker rm -f eco_air_active >/dev/null 2>&1
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$ docker run -d --name eco_air_active -p 8080:8080 -m ${m}m $IMAGE"
  docker run -d --name eco_air_active -p 8080:8080 -m ${m}m $IMAGE
  secs=-2
  for i in $(seq 1 45); do
    s=$(docker logs eco_air_active 2>&1 | grep -oP 'Started EcoAirApplication in \K[\d.]+' | head -1)
    st=$(docker inspect -f '{{.State.Status}}' eco_air_active 2>/dev/null)
    if [ -n "$s" ]; then secs=$s; break; fi
    if [ "$st" != "running" ] && [ $i -gt 2 ]; then secs=-1; break; fi
    sleep 1
  done
  [ "$secs" != "-1" ] && [ "$secs" != "-2" ] && sleep 8
  state=$(docker inspect eco_air_active --format 'Status={{.State.Status}} ExitCode={{.State.ExitCode}} OOMKilled={{.State.OOMKilled}}')
  echo "RESULTADO: ${m}m | arranque=${secs} s | $state"
  if [[ "$state" == *"Status=running"* ]] && awk "BEGIN{exit !($secs>0 && $secs<15)}"; then
    docker stats --no-stream eco_air_active
    found=$m; break
  else
    docker logs --tail 3 eco_air_active 2>&1
  fi
  echo
done
docker rm -f eco_air_active >/dev/null 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] \$ docker run -d --name eco_air_active -p 8080:8080 -m ${found}m $IMAGE"
docker run -d --name eco_air_active -p 8080:8080 -m ${found}m $IMAGE
sleep 20
docker logs --timestamps eco_air_active | grep 'Started EcoAirApplication'
docker stats --no-stream eco_air_active
docker ps -a --filter name=eco_air
echo "UMBRAL_MINIMO_FINAL=${found}m"
date
} 2>&1 | tee -a "$OUT" audit_session.log
