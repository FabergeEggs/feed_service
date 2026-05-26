import Config

# SSL is terminated at the API gateway (KrakenD) level.
# The service itself runs plain HTTP inside the Docker network.
# Do NOT add force_ssl here — KrakenD calls http://feed-service:4000 and
# a 301 redirect would break all requests.

# Do not print debug messages in production.
# Log level can be tuned at runtime via the LOG_LEVEL env var (see runtime.exs).
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.
