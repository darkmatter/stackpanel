{
  "/dev/openai-api-key" = {
    id = "/dev/openai-api-key";
    key = "OPENAI_API_KEY";
    master-keys = [ "local" ];
    type = "SECRET";
  };
  "/prod/postgres-url" = {
    description = "Postgres URL";
    key = "POSTGRES_URL";
    master-keys = [ "local" ];
    type = "SECRET";
  };
  postgres-url = {
    id = "postgres-url";
    key = "postgres-url";
    type = "SECRET";
    value = "";
  };
  postgres-url-dev = {
    id = "postgres-url-dev";
    key = "postgres-url-dev";
    type = "SECRET";
    value = "";
  };
}

