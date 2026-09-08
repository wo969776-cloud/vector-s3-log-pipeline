# --- 1단계: 빌드 ---
FROM maven:3.9-eclipse-temurin-17 AS build
WORKDIR /app
COPY pom.xml .
RUN mvn dependency:go-offline
COPY src ./src
RUN mvn clean package -DskipTests

# --- 2단계: 실행 ---
FROM eclipse-temurin:17-jre
WORKDIR /app
COPY --from=build /app/target/logapp-1.0.0.jar app.jar
EXPOSE 8080
ENTRYPOINT ["java", "-jar", "app.jar"]
