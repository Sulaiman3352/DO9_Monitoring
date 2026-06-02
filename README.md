# DO9 — Monitoring: Behind the Scenes

> An engineering journal of how I turned a working hotel-booking microservices stack
> into one that I could actually **see, measure, and get paged about**.

---

## The setup

I came into this project with a deployment I already knew well: eight Spring Boot
services (`gateway`, `session`, `hotel`, `booking`, `payment`, `loyalty`, `report`)
plus PostgreSQL, RabbitMQ, and an Nginx fronting it all, running on a three-node
Docker Swarm carried over from the previous project. It worked. Requests came in,
bookings were created, messages flowed through RabbitMQ.

But from the outside, the whole thing was a black box. If `booking` started
choking on a queue, or `gateway` started returning 500s, the only way I'd find
out was to SSH in and tail container logs by hand. The task here was to fix
that — wire the cluster up with **Prometheus, Loki, Grafana, and Alertmanager**
so the system could tell me what was wrong before I had to guess.

The full task spec lives in [`../README.md`](../README.md). The implementation
write-up with every panel and screenshot is in [`./REPORT.md`](./REPORT.md).
This document is the **story** — what I planned, what surprised me, and how I
worked around it.

---

## The plan

I split the work the same way the task did, in three layers:

1. **Collect** — instrument the application with Micrometer counters, scrape
   them with Prometheus, ship container logs to Loki via Promtail.
2. **Visualize** — stand up Grafana, point it at both data sources, and build
   one dashboard with fifteen panels that covers infra and application metrics
   side-by-side.
3. **Alert** — run Alertmanager next to Prometheus and route alerts to two
   independent channels (email + Telegram) so a single bad SMTP day couldn't
   blind me.

The architectural decision I made up front was to keep monitoring in its own
stack file (`mon.yml`) joined to the app stack via an **external overlay
network** (`myapp_internal-network`). That kept the two lifecycles independent:
I could redeploy the dashboard without bouncing the booking service, and vice
versa.

---

## Part 1 — Teaching the app to talk

### Approach

Spring Boot's Actuator already ships with Micrometer baked in. So for HTTP-level
metrics (gateway requests, auth requests) I didn't have to write a line of Java
— enabling the Prometheus endpoint was three lines in `application.properties`:

```properties
server.port=<port>
management.endpoints.web.exposure.include=prometheus,health,info
management.endpoint.prometheus.enabled=true
```

That alone gave me `http_server_requests_seconds_count` with `uri`, `method`,
and `status` labels — enough to separate "total gateway traffic" from
"authorization requests on `/api/v1/auth/authorize`" with two different PromQL
queries against the same series.

The custom counters needed real code. Three places mattered:

- `QueueProducer.java` (booking-service) — increment when a message is sent to
  RabbitMQ.
- `QueueConsumer.java` (report-service) — increment when a message is
  successfully consumed.
- `BookingServiceImplementation.java` (booking-service) — increment per
  booking created.

The pattern was the same each time: inject `MeterRegistry`, build a `Counter`
in the constructor, call `.increment()` at the right line. Exact diffs are in
the report.

### The snag — `build:` vs `image:`

The first redeploy failed instantly. The original compose file used
`build: ./services/booking` to compile each image from source on the swarm
host — fine on a single dev machine, useless across three nodes because only
the manager had the source tree.

The fix was mechanical but tedious: build each service locally, tag it
(`sulaiman3352/booking:2.4.x`), push to Docker Hub, switch every `build:`
block in `docker-compose.yml` to `image: sulaiman3352/<name>:<tag>`. After
that, any node could pull and run any service. I bumped tags whenever I
re-instrumented a service so I could roll back if a counter wiring broke
something.

### The snag — "the counter is zero, is it broken?"

After deploy, the dashboards were flat. Not zero-because-broken — zero-because
**nothing had happened yet**. A `Counter` only moves when its line executes,
and my fresh stack had no users hitting it.

The fix was to manually trigger the flows that the counters watched:

```bash
docker exec <nginx-container-id> curl -v \
  -H "Authorization: Bearer fake-token" \
  http://session:8081/api/v1/auth/authorize

docker exec -it <booking-container> curl -s \
  http://localhost:8083/actuator/prometheus | grep rabbitmq_messages_sent
```

This is obvious in hindsight but cost me a half hour of "is Prometheus
broken? is the scrape config wrong?" debugging. **Lesson banked**: when a
metric is at zero, prove the underlying event has fired *before* you blame
the pipeline.

### Logs — Promtail, the quiet one

Loki was the easy part of part 1 once I realized Promtail had to run as a
**global service** on every node (`deploy: mode: global`) and needed
`/var/lib/docker/containers` and `/var/run/docker.sock` mounted read-only.
Container logs in Docker Swarm land in JSON files under that containers
directory; Promtail tails them, tags each line with the
`swarm_service` / `container_name` labels, and ships them to Loki.

---

## Part 2 — Making it look like something

With data flowing, the dashboard came together fast. The interesting work
wasn't in Grafana's UI — it was in writing PromQL that actually answered the
question on the panel title.

A few that took thought:

| Question | Query |
|---|---|
| Number of stacks | `count(count by (container_label_com_docker_stack_namespace) (container_last_seen{container_label_com_docker_stack_namespace!=""}))` |
| CPU per service | `sum(rate(container_cpu_usage_seconds_total{container_label_com_docker_swarm_service_name!=""}[1m])) by (container_label_com_docker_swarm_service_name)` |
| google.com reachability | `probe_success{instance="https://www.google.com"}` |
| Bookings in last hour | `sum(increase(app_bookings_created_total[1h]))` |

The double-`count` for stacks took me a minute — the first `count` collapses
per-container series into one-per-stack-label, the outer `count` then counts
the stacks. It's the kind of PromQL that reads wrong until you trace it from
the inside out.

For google.com I used the **blackbox_exporter** with a relabel trick: the URL
under `targets:` is rewritten into the `target` query parameter, and the actual
scrape address is swapped to `blackbox_exporter:9115`. That's the canonical
pattern but it always feels a little magical the first time.

The final dashboard layout, query list, and per-panel screenshot is in
[`REPORT.md`](./REPORT.md) (screenshots `006.png` through `023.png`).

---

## Part 3 — Alerting, and the wall I hit

### Approach

Alertmanager runs in `mon.yml` alongside Prometheus. The three required rules
live in `alert-rules.yml`:

- Available memory below 100 MB → critical
- Used RAM above 1 GB → critical
- Per-service CPU above 10% → critical

Each one fires after a one-minute `for:` window so a momentary spike doesn't
page me. The receivers in `alertmanager.yml` are two: **SMTP via Yandex** for
email, and a **Telegram bot** posting into my personal chat. Email is the
durable record; Telegram is the wake-me-up channel.

### The wall — Telegram is blocked

This is where the project stopped being a checklist and started being real
engineering.

**Telegram is blocked at the network level where I run my swarm.** I'd
configured the bot token and chat ID correctly, the alert rules fired correctly,
Alertmanager logs showed the dispatch attempt — and then a connection timeout
to `api.telegram.org`. Email was arriving on Yandex within seconds. Telegram
was silently dropping into the void.

The clean fix would have been an outbound proxy, but I didn't want to bolt a
new piece of infrastructure onto the stack just for this. What I did instead:

1. Confirmed it wasn't an auth or formatting problem by curl-ing the
   Telegram Bot API directly from inside the `alertmanager` container —
   same timeout, so the issue was definitely network reachability, not
   credentials.
2. Routed the host's outbound traffic through a **VPN tunnel**, so any
   container on the swarm (Alertmanager included) would egress through it
   without needing per-container proxy config.
3. Re-fired a test alert by deliberately tripping the
   `HighServiceCPU` rule and watched the message land in Telegram within
   the expected `group_wait` window.

The takeaway wasn't really about Telegram — it was that **monitoring is
worthless if the notification channel can't actually leave your network.**
I'd built the whole pipeline and very nearly shipped it with the
loudest-priority channel silently broken. Now I always end an alerting setup
with a forced trigger that I watch land on every channel end-to-end.

### The snag — triggering the alerts on purpose

Same flavor of problem as part 1: the CPU rule needed real CPU load to fire.
I generated it by hammering the gateway with a loop of authenticated curl
requests until the per-service rate crossed 10%. Crude but it worked, and it
double-checked that the `container_label_com_docker_swarm_service_name`
label was actually populated on the series (it is, because of cAdvisor's
default labeling of Swarm containers).

---

## The final shape

```
              ┌──────────────────────────────────────────┐
              │              Grafana :3000               │
              │   one dashboard, infra + app + logs      │
              └──────────────────────────────────────────┘
                  ▲                          ▲
                  │ PromQL                   │ LogQL
                  │                          │
        ┌─────────┴─────────┐      ┌─────────┴─────────┐
        │ Prometheus :9090  │      │     Loki :3100    │
        │  ─ scrape jobs ─  │      │                   │
        └─────────┬─────────┘      └─────────┬─────────┘
                  │                          │
   ┌──────────────┼──────────────┐           │
   ▼              ▼              ▼           │
 node_exp      cAdvisor      blackbox    Promtail (global)
   (host)    (containers)   (probes)         │
                                             ▼
                                  /var/lib/docker/containers
                                  ──────────────────────────
                                     8 Spring Boot services
                                     (Micrometer counters)

        ┌──────────────────┐
        │ Alertmanager     │ ── email (Yandex SMTP) ──▶ inbox
        │  :9093           │ ── Telegram via VPN ─────▶ phone
        └──────────────────┘
```

Everything lives in [`src/01/docker/monitoring/`](./01/docker/monitoring/):

- `mon.yml` — the monitoring stack
- `prometheus.yml` — scrape jobs + blackbox relabeling + alert rule loader
- `alert-rules.yml` — three critical rules with sensible `for:` windows
- `alertmanager.yml` — email + Telegram receivers, grouping, inhibit rules
- `promtail-config.yml` — Docker log discovery + Loki push

---

## What I'd do differently next time

- **Build a synthetic load generator into the dev workflow** instead of
  hand-curling endpoints to coax counters to move. Even a tiny background
  script that hits the booking flow every minute would have shortened the
  feedback loop on every dashboard panel.
- **Verify outbound reachability for every notification channel as step
  zero**, not after wiring the rules. A 30-second `curl api.telegram.org`
  from the host would have surfaced the block before I touched any config.
- **Store credentials as Docker secrets** instead of inline in
  `alertmanager.yml`. Fine for a school project, not for anything that
  would touch a real inbox.

---

## Stack

`Docker Swarm` · `Spring Boot` · `Micrometer` · `Prometheus` · `Loki` ·
`Promtail` · `Grafana` · `Alertmanager` · `cAdvisor` · `node_exporter` ·
`blackbox_exporter` · `RabbitMQ` · `PostgreSQL` · `Nginx`
# DO9_Monitoring
# DO9_Monitoring
# DO9_Monitoring
# DO9_Monitoring
# DO9_Monitoring
