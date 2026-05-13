# Thin wrapper on the official Hermes image so Railway's dynamic PORT reaches the API server.
# Data volume: mount at /opt/data (Hermes default HERMES_HOME in the upstream image).
FROM nousresearch/hermes-agent:latest
USER root
COPY clawdeez-railway-entry.sh /clawdeez-railway-entry.sh
RUN chmod 0755 /clawdeez-railway-entry.sh
ENTRYPOINT ["/clawdeez-railway-entry.sh"]
CMD ["gateway", "run"]
