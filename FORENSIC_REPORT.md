# FORENSIC REPORT – eco-air-backend

**Operador:** Nicolás Bastidas  
**STUDENT_ID / OPERATOR_ID:** 890275  
**Fecha de la auditoría:** 2026-10-21 (12:43 – 14:40, hora Colombia)  
**Entorno:** Fedora Linux 43 · Kernel 7.1.12 · Docker 29.6.2 · cgroup v2 · 12 CPU · 31 GiB RAM

---

## 1. Tabla de identidad

| Campo | Valor |
|---|---|
| Imagen | `eco-air-backend:1.0.0` |
| Image ID | `sha256:568e9b8ed17b3220e091a657f8347c59af87992c3f1538e49811a90b0b94fbf2` |
| Tamaño (contenido / disco) | 159 MB / 453 MB |
| Label `operator.id` | `890275` |
| `OPERATOR_ID` dentro del contenedor | `OPERATOR_ID=890275` |
| Usuario de ejecución | `sensor_user` (UID 10001) |
| Umbral mínimo de memoria | **96 MB** |
| Contenedor final | `eco_air_active` (`-m 96m`) |

```
$ docker inspect --format='{{.Id}}' eco-air-backend:1.0.0
sha256:568e9b8ed17b3220e091a657f8347c59af87992c3f1538e49811a90b0b94fbf2

$ docker exec eco_air_active env | grep OPERATOR_ID
OPERATOR_ID=890275

$ docker stats --no-stream eco_air_active
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O       PIDS
4c60da47abe2   eco_air_active   0.15%     82.89MiB / 96MiB    86.35%    5.95kB / 126B   220MB / 311MB   31
```

---

## 2. Reto 1 – Construcción multietapa

```
$ docker build --build-arg STUDENT_ID="890275" -t eco-air-backend:1.0.0 .
...
#14 19.24 [INFO] Building jar: /build/target/eco-air-backend.jar
#14 DONE 20.0s
#17 naming to docker.io/library/eco-air-backend:1.0.0 done
(exit code: 0)

$ docker images eco-air-backend:1.0.0
IMAGE                   ID             DISK USAGE   CONTENT SIZE
eco-air-backend:1.0.0   568e9b8ed17b        453MB          159MB

$ docker image inspect eco-air-backend:1.0.0 --format 'Labels: {{json .Config.Labels}} | User: {{.Config.User}}'
Labels: {"operator.id":"890275"} | User: sensor_user
```

**Interpretación:** la build termina sin errores. La imagen final hereda de `eclipse-temurin:17-jre-alpine` y lleva el label y el usuario no root definidos en el Dockerfile.

---

## 3. Reto 2 – Auditoría forense

### 3.1 Historial de capas

```
$ docker history --human --format 'table {{.Size}}\t{{.CreatedBy}}' eco-air-backend:1.0.0
SIZE      CREATED BY
0B        ENTRYPOINT ["java" "-jar" "/app/app.jar"]
0B        EXPOSE [8080/tcp]
0B        USER sensor_user
0B        ENV OPERATOR_ID=890275 JAVA_TOOL_OPTIONS=-XX…
48.9MB    RUN |1 STUDENT_ID=890275 /bin/sh -c chown -R…
48.9MB    COPY /build/target/*.jar app.jar # buildkit
0B        WORKDIR /app
24.6kB    RUN |1 STUDENT_ID=890275 /bin/sh -c addgroup…
0B        LABEL operator.id=890275
0B        ARG STUDENT_ID=890275
0B        ENTRYPOINT ["/__cacert_entrypoint.sh"]
8.19kB    COPY --chmod=755 entrypoint.sh /__cacert_ent…
0B        RUN /bin/sh -c set -eux;     echo "Verifying…
142MB     RUN /bin/sh -c set -eux;     ARCH="$(apk --p…
0B        ENV JAVA_VERSION=jdk-17.0.20.1+1
44.8MB    RUN /bin/sh -c set -eux;     apk add --no-ca…
0B        ENV LANG=en_US.UTF-8 LANGUAGE=en_US:en LC_AL…
0B        ENV PATH=/opt/java/openjdk/bin:/usr/local/sb…
0B        ENV JAVA_HOME=/opt/java/openjdk
0B        CMD ["/bin/sh"]
10.1MB    ADD alpine-minirootfs-3.24.2-x86_64.tar.gz /…
```

**Interpretación:** solo aparecen las capas de Alpine, del JRE 17 y de `app.jar`. No hay ninguna capa de Maven (`mvn`), de `pom.xml` ni de `src/`. La etapa builder no llegó a la imagen final.

### 3.2 Proceso en el host

```
$ docker top eco_air_active -o pid,user,comm
PID                 USER                COMMAND
120340              10001               java

$ docker exec eco_air_active id
uid=10001(sensor_user) gid=101(sensorgroup) groups=101(sensorgroup)

$ curl -s http://localhost:8080/api/health
{"status":"UP","operator":"890275"}
```

**Interpretación:** desde el host, el proceso `java` corre con UID 10001 y no con root (UID 0). La API responde.

### 3.3 Inmutabilidad de runtime

```
$ docker exec eco_air_active touch /etc/crontab_fake
touch: cannot touch '/etc/crontab_fake': Permission denied
(exit code: 1)

$ docker exec eco_air_active ls -ld /etc /app
drwxr-xr-x 1 sensor_user sensorgroup 14 Oct 21 17:53 /app
drwxr-xr-x 1 root        root        56 Oct 21 17:53 /etc
```

**Interpretación:** `/etc` pertenece a root. El usuario del contenedor no puede crear ni modificar archivos del sistema, así que no puede dejar persistencia como un cron falso.

### 3.4 Artefactos de desarrollo

```
$ docker exec eco_air_active which mvn
(exit code: 1)

$ docker exec eco_air_active find / -name '*.java' 2>/dev/null
(exit code: 1)

$ docker exec eco_air_active ls -la /app
-rw-r--r-- 1 sensor_user sensorgroup 48944322 Oct 21 17:53 app.jar
```

**Interpretación:** no existe `mvn` ni ningún `.java` en la imagen. En `/app` solo está el artefacto compilado.

---

## 4. Reto 3 – Límites de memoria (cgroups v2)

### 4.1 Colapso con 48 MB

```
$ docker run -d --name eco_air_crash -m 48m eco-air-backend:1.0.0
d3e3112b9e8d7193227a485baa1b61d6c7989e28afdb4393ce639801bbe67df4

$ docker inspect eco_air_crash --format='Status: {{.State.Status}} | ExitCode: {{.State.ExitCode}} | OOMKilled: {{.State.OOMKilled}}'
Status: exited | ExitCode: 137 | OOMKilled: true

$ docker inspect eco_air_crash --format='Memory limit (bytes): {{.HostConfig.Memory}}'
Memory limit (bytes): 50331648
```

Últimas líneas del log antes de morir:
```
... Bootstrapping Spring Data JPA repositories in DEFAULT mode.
... Finished Spring Data repository scanning in 200 ms. Found 1 JPA repository interface.
```

**Interpretación:** el proceso pasó el límite del cgroup (50 331 648 bytes = 48 MiB) mientras Spring arrancaba. El kernel lo mató con SIGKILL: código 137 = 128 + 9, con `OOMKilled: true`. La JVM no alcanzó a cerrarse por su cuenta.

### 4.2 Calibración del límite mínimo

Criterio: arrancar en menos de 15 s y seguir `running` 8 s después del arranque.

| Límite | Arranque | Estado tras 8 s | ¿Cumple? |
|---|---|---|---|
| 64m | no arrancó | exited · 137 · OOMKilled=true | No |
| 72m | no arrancó | exited · 137 · OOMKilled=true | No |
| 80m | no arrancó | exited · 137 · OOMKilled=true | No |
| 88m | 11.281 s | exited · 137 · OOMKilled=true | No (muere después de arrancar) |
| **96m** | **7.298 s** (1.ª corrida) / **8.085 s** (2.ª corrida) | **running · 0 · OOMKilled=false** | **Sí** |

**Umbral mínimo: 96 MB.**

```
$ docker run -d --name eco_air_active -p 8080:8080 -m 96m eco-air-backend:1.0.0
4c60da47abe2d34e27d0104f89da29a2ef76ce1d05afe25cdf60fca2ccfc6073

$ docker logs --timestamps eco_air_active | grep 'Started EcoAirApplication'
2026-10-21T19:40:15.219672309Z ... Started EcoAirApplication in 8.085 seconds (process running for 8.883)

$ docker stats --no-stream eco_air_active
CONTAINER ID   NAME             CPU %     MEM USAGE / LIMIT   MEM %     NET I/O         BLOCK I/O       PIDS
4c60da47abe2   eco_air_active   0.15%     82.89MiB / 96MiB    86.35%    5.95kB / 126B   220MB / 311MB   31

$ docker ps -a --filter name=eco_air
CONTAINER ID   IMAGE                   STATUS                     PORTS                    NAMES
4c60da47abe2   eco-air-backend:1.0.0   Up 21 seconds              0.0.0.0:8080->8080/tcp   eco_air_active
d3e3112b9e8d   eco-air-backend:1.0.0   Exited (137) 2 hours ago                            eco_air_crash
```

**Interpretación:** con 88 MB la app alcanza a arrancar, pero el kernel la mata segundos después, así que ese límite no es estable. Con 96 MB arranca en unos 8 s y se mantiene en reposo en ~83 MiB (86 %), por debajo del límite.

---

## 5. Evidencia cruda

Todas las salidas anteriores están completas, con hora, en `audit_session.log`.
