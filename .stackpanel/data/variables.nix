{
  "/common/SHARED_VALUE" = {
    id = "/common/SHARED_VALUE";
    value = "secret value";
  };
  "/dev/OPENAI_API_KEY" = {
    value = "ref+sops://.stackpanel/secrets/dev.yaml#/OPENAI_API_KEY";
  };
  "/foobar" = {
    id = "/foobar";
    key = "foobar";
    type = "SECRET";
    value = "";
  };
  "/my-api-endpoint" = {
    id = "/my-api-endpoint";
    value = "cool-api.com";
  };
  "/prod/POSTGRES_URL" = {
    value = "ref+sops://.stackpanel/secrets/prod.yaml#/POSTGRES_URL";
  };
  "/secret-foo" = {
    id = "/secret-foo";
    key = "secret-foo";
    type = "SECRET";
    value = "";
  };
  "/stripe-secre-key" = {
    id = "/stripe-secre-key";
    value = "ref+sops://.stackpanel/secrets/common.yaml#/KEY";
  };
  "/test" = {
    id = "/test";
    key = "test";
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

