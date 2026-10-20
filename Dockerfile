# ---------- Etapa 1: builder ----------
FROM maven:3.9.6-eclipse-temurin-17-alpine AS builder
ARG STUDENT_ID
WORKDIR /build

# Solo el pom primero -> la capa de dependencias queda en caché
COPY pom.xml .
RUN mvn dependency:go-offline -B

# Ahora el código fuente
COPY src ./src
RUN echo "Build por: ${STUDENT_ID}" && mvn package -DskipTests -B

# ---------- Etapa 2: runtime ----------
FROM eclipse-temurin:17-jre-alpine
# ARG se pierde entre etapas: hay que redeclararlo
ARG STUDENT_ID
LABEL operator.id="${STUDENT_ID}"

RUN addgroup -S sensorgroup && \
    adduser -S -D -H -u 10001 -G sensorgroup sensor_user

WORKDIR /app
COPY --from=builder /build/target/*.jar app.jar
RUN chown -R sensor_user:sensorgroup /app

ENV OPERATOR_ID=${STUDENT_ID} \
    JAVA_TOOL_OPTIONS="-XX:+UseContainerSupport -XX:MaxRAMPercentage=75.0 -XX:InitialRAMPercentage=50.0 -XX:+UseSerialGC -XX:+ExitOnOutOfMemoryError"

USER sensor_user
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "/app/app.jar"]
