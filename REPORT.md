## Part 1
- To run my latest Docker Swarm I needed to do some changes to Dockerfile and then change image section from docker-compose.yml to build.
- And then I start to push them to docker hub to run the stack using image instate of build.
- ![](./img/001.png)
- ![](./img/002.png)
- I used the next dockerfile for services: 
```
FROM maven:3.8.5-openjdk-17 AS build
WORKDIR /app

COPY pom.xml .
RUN mvn dependency:go-offline

COPY src ./src
RUN mvn clean package -DskipTests

FROM eclipse-temurin:8-jdk
WORKDIR /app

COPY --from=build /app/target/*.jar app.jar

COPY wait-for-it.sh /wait-for-it.sh
RUN chmod +x /wait-for-it.sh

EXPOSE <port>

ENTRYPOINT ["/wait-for-it.sh", "postgres:5432", "--", "java", "-jar", "app.jar"]

```
- and my `docker-compose.yml` file is
```

services:
  # --- INFRASTRUCTURE ---
  postgres:
    image: "postgres:15.1-alpine"
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: default_database
    volumes:
      - shop_postgres:/var/lib/postgresql/data
      - /home/vagrant/services/database:/docker-entrypoint-initdb.d
    networks:
      - internal-network 
    deploy:
      placement:
        constraints: [node.role == manager]

  rabbitmq:
    image: rabbitmq:3-management-alpine
    networks:
      - internal-network

  # --- PROXY ---
  nginx:
    image: nginx:latest
    ports:
      - "80:80"  # Access gateway via http://localhost/gateway and session via http://localhost/session
    configs:
      - source: nginx_conf_v1
        target: /etc/nginx/nginx.conf
    networks:
      - internal-network
    deploy:
      replicas: 1
      restart_policy:
        condition: on-failure

  # --- APP SERVICES ---
  session:
    image: sulaiman3352/session:2.4.1
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: users_db
    depends_on:
      - postgres
      - rabbitmq
    networks:
      - internal-network

  gateway:
    image: sulaiman3352/gateway:2.4.1
    environment:
      SPRING_DATASOURCE_URL: jdbc:postgresql://postgres:5432/users_db
      SPRING_DATASOURCE_USERNAME: postgres
      SPRING_DATASOURCE_PASSWORD: password 
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
      SERVER_PORT: 8087
      SESSION_SERVICE_HOST: session
      SESSION_SERVICE_PORT: 8081
      HOTEL_SERVICE_HOST: hotel
      HOTEL_SERVICE_PORT: 8082
      BOOKING_SERVICE_HOST: booking
      BOOKING_SERVICE_PORT: 8083
      PAYMENT_SERVICE_HOST: payment
      PAYMENT_SERVICE_PORT: 8084
      LOYALTY_SERVICE_HOST: loyalty
      LOYALTY_SERVICE_PORT: 8085
      REPORT_SERVICE_HOST: report
      REPORT_SERVICE_PORT: 8086
    depends_on:
      - postgres
      - rabbitmq
      - session
    networks:
      - internal-network
    deploy:
      replicas: 1
      placement:
        constraints: [node.role == manager]

  hotel:
    image: sulaiman3352/hotel:2.4.1
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: hotels_db
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
    networks:
      - internal-network

  loyalty:
    image: sulaiman3352/loyalty:2.4.1
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: balances_db
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
    networks:
      - internal-network

  booking:
    image: sulaiman3352/booking:2.4.31
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: reservations_db
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
      RABBIT_MQ_HOST: rabbitmq
      RABBIT_MQ_PORT: 5672
      RABBIT_MQ_USER: guest
      RABBIT_MQ_PASSWORD: guest
      RABBIT_MQ_QUEUE_NAME: messagequeue
      RABBIT_MQ_EXCHANGE: messagequeue-exchange
      HOTEL_SERVICE_HOST: hotel
      HOTEL_SERVICE_PORT: 8082
      PAYMENT_SERVICE_HOST: payment
      PAYMENT_SERVICE_PORT: 8084
      LOYALTY_SERVICE_HOST: loyalty
      LOYALTY_SERVICE_PORT: 8085
    networks:
      - internal-network

  report:
    image: sulaiman3352/report:2.4.3
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: statistics_db
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
      RABBIT_MQ_HOST: rabbitmq
      RABBIT_MQ_PORT: 5672
      RABBIT_MQ_USER: guest
      RABBIT_MQ_PASSWORD: guest
      RABBIT_MQ_QUEUE_NAME: messagequeue
      RABBIT_MQ_EXCHANGE: messagequeue-exchange
    networks:
      - internal-network

  payment:
    image: sulaiman3352/payment:2.4.1
    environment:
      POSTGRES_HOST: postgres
      POSTGRES_PORT: 5432
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: password
      POSTGRES_DB: payments_db
      SPRING_JPA_DATABASE_PLATFORM: org.hibernate.dialect.PostgreSQLDialect
      SPRING_DATASOURCE_DRIVER_CLASS_NAME: org.postgresql.Driver
      SPRING_JPA_HIBERNATE_DDL_AUTO: update
    networks:
      - internal-network 

  # --- MONITORING ---
  prometheus:
    image: prom/prometheus:latest
    ports:
      - "9090:9090" # access the Prometheus UI from browser on port 9090
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - internal-network
    deploy:
      placement:
        constraints: [node.role == manager]

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000" # Maps the Grafana web UI
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=admin
    networks:
      - internal-network
    deploy:
      placement:
        constraints: [node.role == manager]
  loki:
    image: grafana/loki:latest
    ports:
      - "3100:3100"
    networks:
      - internal-network
    deploy:
      placement:
        constraints: [node.role == manager]

  promtail:
    image: grafana/promtail:latest
    volumes:
      # This allows Promtail to read the raw log files generated by Docker
      - /var/lib/docker/containers:/var/lib/docker/containers:ro
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - ./promtail-config.yml:/etc/promtail/config.yml
    command: -config.file=/etc/promtail/config.yml
    networks:
      - internal-network
    deploy:
      mode: global

volumes:
  shop_postgres:

configs:
  nginx_conf_v1:
    file: ./nginx.conf

networks:
  internal-network:
    external: true
    name: myapp_internal-network


```

- We need to setup MeterRegistry to connect our applications to Prometheus by adding the next lines to file application.properties

```
server.port=<port>
management.endpoints.web.exposure.include=prometheus,health,info
management.endpoint.prometheus.enabled=true
```

- Then build and use the updated image
- ![](./img/003.png)
- ![](./img/027.png)
- After running the stack I access Grafana via browser and add source:
- ![](./img/004.png)
- ![](./img/005.png)
- Then I start to add panels for the task:


- To get number of messages sent to rabbitmq I needed to modify file QueueProducer.java and add the next lines
```
(lines 6-7):
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
(lines 18-19):
private final RabbitTemplate rabbitTemplate;
private final Counter messageCounter;
@Autowired
(lines 23-29):
public QueueProducer(RabbitTemplate rabbitTemplate, MeterRegistry meterRegistry) {
    this.rabbitTemplate = rabbitTemplate;
    this.messageCounter = Counter.builder("rabbitmq_messages_sent")
        .description("Total messages sent to RabbitMQ")
        .register(meterRegistry);
}
(line 35):
messageCounter.increment();
```

- And now to get number of messages processed in rabbitmq I add these lines to file QueueConsumer.java
```
// 1. Add Micrometer imports
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;
// 2. Make dependencies private final
private final BookingStatsService bookingStatsService;
private final Counter processedCounter;
private ObjectMapper objectMapper = new ObjectMapper();

// 3. Use constructor injection for both the service and the registry
public QueueConsumer(BookingStatsService bookingStatsService, MeterRegistry meterRegistry) {
    this.bookingStatsService = bookingStatsService;
    this.processedCounter = Counter.builder("rabbitmq_messages_processed")
            .description("Total messages successfully processed from RabbitMQ")
            .register(meterRegistry);
}
// 4. Increment the counter at the very end!
processedCounter.increment();
System.out.println("Message processed and counter incremented!");
```

- For the last one; number of bookings I add the next lines to BookingServiceImplementation.java
```
import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

private final Counter bookingCounter;
    @Autowired
    public BookingServiceImplementation(MeterRegistry meterRegistry) {
        this.bookingCounter = Counter.builder("app_bookings_created")
                .description("Total number of hotel bookings created")
                .register(meterRegistry);
    }
    
    bookingCounter.increment();
```

- For "number of requests received at the gateway" and "number of user authorization requests received", no custom Micrometer code was needed. Spring Boot Actuator automatically instruments all incoming HTTP requests through its built-in Micrometer integration, exposing them as the `http_server_requests_seconds_count` metric with labels for `uri`, `method`, and `status`.
- This is enabled by the same `application.properties` setting I already added earlier: `management.endpoints.web.exposure.include=prometheus,health,info management.endpoint.prometheus.enabled=true`
- Once Prometheus scrapes the `/actuator/prometheus` endpoint of the gateway, all request counts become queryable. I used the labels to separate total gateway requests from the specific authorization endpoint:
  - Total gateway requests: `sum(rate(http_server_requests_seconds_count{instance="gateway:8087"}[5m])) by (uri)`
  - Authorization requests only: `sum(increase(http_server_requests_seconds_count{uri="/api/v1/auth/authorize", method="GET"}[1h]))`


- For readying logs from Grafana we add first Loki as a source
- ![source](./img/011.png)

- last thing I moved the stack for monitoring to a spirit folder under folder monitoring with name mon.yml 

## Part 2
- For visualizing "number of requests received at the gateway" We need first trigger with `docker exec <nginx-container-id> curl -v -H "Authorization: Bearer fake-token" http://session:8081/api/v1/auth/authorize` 
- and add to Grafana `sum(rate(http_server_requests_seconds_count{instance="gateway:8087"}[5m])) by (uri)`
- ![requests gateway](./img/006.png)
#
- For "number of messages sent to rabbitmq" I needed to trigger a Message `docker exec -it <container-id> curl -s http://localhost:8083/actuator/prometheus | grep rabbitmq_messages_sent` 
- then add the next query to Grafana `sum(increase(rabbitmq_messages_sent_total[1h]))`
- ![messages sent to rabbitmq](./img/008.png)
#
- And for "number of messages processed in rabbitmq": `sum(increase(rabbitmq_messages_processed_total[1h]))`
- ![messages processed in rabbitmq](./img/009.png)
#
- To add number of bookings `sum(increase(app_bookings_created_total[1h]))`
- ![number of bookings](./img/010.png)
#
- "number of user authorization requests received":`sum(increase(http_server_requests_seconds_count{uri="/api/v1/auth/authorize", method="GET"}[1h]))`
- ![authorization requests](./img/007.png)
#
- For reading logs, Now from Explore we can just filter swarm_service then the container we want to check his logs
- ![source](./img/012.png)
#
- Now the time to visualize availability of google and I added this line "- https://www.google.com" in file prometheus.yml and then I added query "probe_success{instance="https://www.google.com"}" in  Grafana panel.
- ![google](./img/013.png)
#
- For Number of Nodes because we have already exporter; We need just to add query "count(up{job="node-exporter"})"
- ![n nodes](./img/014.png)
#
- Because we deployed cAdvisor, now we need just to add query "count(container_last_seen{image!=""})"
- ![n cont](./img/015.png)
#
- For Number of Stacks I add this query "count(count by (container_label_com_docker_stack_namespace) (container_last_seen{container_label_com_docker_stack_namespace!=""}))"
- ![n stack](./img/016.png)
#
- For CPU Usage for Services I added "sum(rate(container_cpu_usage_seconds_total{ container_label_com_docker_swarm_service_name!="" }[1m])) by (container_label_com_docker_swarm_service_name)"
- ![cpu services](./img/017.png)
#
- And for CPU Usage for Cores "100 - (rate(node_cpu_seconds_total{mode="idle"}[1m]) * 100)" and Nodes "100 - (avg by(instance)(rate(node_cpu_seconds_total{mode="idle"}[1m])) * 100)"
- ![cpu core](./img/018.png)
- ![cpu node](./img/019.png)
#
- memory usage "node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes" also "(node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) / node_memory_MemTotal_bytes * 100" and for free memory "node_memory_MemAvailable_bytes"
- ![mem usa](./img/020.png)
- ![mem usa](./img/021.png)
- ![mem free](./img/022.png)
#
- For Number of CPUs "count without(cpu, mode) (node_cpu_seconds_total{mode="idle"})"
- ![n cpu](./img/023.png)

## Part 3 
- for this task I create two file first one is called alertmanager.yml
```
global:
  resolve_timeout: 5m

route:
  group_by: ['alertname']
  group_wait: 30s
  group_interval: 5m
  repeat_interval: 1h
  receiver: 'all-notifications'

receivers:
  - name: 'all-notifications'
    email_configs:
      - to: 'sulaiman3352@gmail.com'
        from: 'sulaiman3352@yandex.ru'
        smarthost: 'smtp.yandex.ru:465'
        auth_username: 'sulaiman3352@yandex.ru'
        auth_password: 'password'
        require_tls: true
        send_resolved: true

    telegram_configs:
      - bot_token: 'token'
        chat_id: 439932381
        message: |
          {{ range .Alerts }}
          *Alert:* {{ .Annotations.summary }}
          *Description:* {{ .Annotations.description }}
          *Severity:* {{ .Labels.severity }}
          {{ end }}
        send_resolved: true

inhibit_rules:
  - source_match:
      severity: 'critical'
    target_match:
      severity: 'warning'
    equal: ['alertname']
```
- and then I created another file called alert-rules.yml 
```
groups:
  - name: infrastructure-alerts
    rules:

      # 1. Available memory less than 100 MB
      - alert: LowAvailableMemory
        expr: node_memory_MemAvailable_bytes < 100 * 1024 * 1024
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "Low available memory on {{ $labels.instance }}"
          description: "Available memory is {{ $value | humanize }}B — below 100 MB threshold."

      # 2. Used RAM more than 1 GB
      - alert: HighUsedRAM
        expr: (node_memory_MemTotal_bytes - node_memory_MemAvailable_bytes) > 1 * 1024 * 1024 * 1024
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "High RAM usage on {{ $labels.instance }}"
          description: "Used RAM is {{ $value | humanize }}B — exceeds 1 GB threshold."

      # 3. CPU usage for a service exceeds 10%
      - alert: HighServiceCPU
        expr: sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_swarm_service_name!=""}[1m])) by (container_label_com_docker_swarm_service_name) > 0.10
        for: 1m
        labels:
          severity: critical
        annotations:
          summary: "High CPU usage for service {{ $labels.container_label_com_docker_swarm_service_name }}"
          description: "CPU usage is {{ $value | humanizePercentage }} — exceeds 10% threshold."
```
- In mon.yml file I added in volume `- ./alert-rules.yml:/etc/prometheus/alert-rules.yml` and the next part:
```
alertmanager:
    image: prom/alertmanager:latest
    ports:
      - "9093:9093"   # UI accessible at http://localhost:9093
    volumes:
      - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml
    command:
      - '--config.file=/etc/alertmanager/alertmanager.yml'
    networks:
      - internal-network
    deploy:
      placement:
        constraints: [node.role == manager]
```
- ![alert](./img/024.png)
- ![alert](./img/025.png)
