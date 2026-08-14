FROM eclipse-temurin:17-jre-jammy

RUN groupadd --system --gid 10001 location \
    && useradd --system --uid 10001 --gid location --home-dir /app location

WORKDIR /app
COPY --chown=10001:10001 location-service.jar /app/location-service.jar

USER 10001:10001
EXPOSE 8080

ENTRYPOINT ["java", "-XX:MaxRAMPercentage=70.0", "-jar", "/app/location-service.jar"]
