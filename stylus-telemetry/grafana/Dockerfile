FROM grafana/grafana-oss:latest

RUN grafana-cli plugins install frser-sqlite-datasource

ENV GF_PLUGINS_ALLOW_LOADING_UNSIGNED_PLUGINS=frser-sqlite-datasource

COPY provisioning /etc/grafana/provisioning
