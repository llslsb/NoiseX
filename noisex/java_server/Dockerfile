# 本地预打包 JAR，直接复制（构建速度快 10x）
FROM eclipse-temurin:17-jre-alpine
WORKDIR /app
COPY target/noisex-server-1.0.0.jar app.jar
EXPOSE 7070
ENV JAVA_OPTS="-Xms512m -Xmx2g -XX:+UseG1GC"
ENTRYPOINT ["sh", "-c", "java $JAVA_OPTS -jar app.jar"]
