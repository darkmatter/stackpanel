{
  "/common/SHARED_VALUE" = {
    id = "/common/SHARED_VALUE";
    value = "secret value1";
  };
  "/dev/OPENAI_API_KEY" = {
    value = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/OPENAI_API_KEY";
  };
  "/foobar" = {
    id = "/foobar";
    key = "foobar";
    type = "SECRET";
    value = "";
  };
  "/my-api-endpoint" = {
    id = "/my-api-endpoint";
    key = "my-api-endpoint";
    type = "SECRET";
    value = "";
  };
  "/prod/POSTGRES_URL" = {
    value = "ref+sops://.stackpanel/secrets/groups/prod.yaml#/POSTGRES_URL";
  };
  "/secret-foo" = {
    id = "/secret-foo";
    key = "secret-foo";
    type = "SECRET";
    value = "";
  };
  "/stripe-secre-key" = {
    id = "/stripe-secre-key";
    value = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/KEY";
  };
  "/test" = {
    id = "/test";
    key = "test";
    type = "SECRET";
    value = "";
  };
  "/username" = {
    id = "/username";
    key = "username";
    type = "SECRET";
    value = "";
  };
  "/var/API_VERSION" = {
    value = "v1";
  };
  "/var/LOG_LEVEL" = {
    value = "info";
  };
}

