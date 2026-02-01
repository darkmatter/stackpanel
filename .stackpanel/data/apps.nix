{
  docs = {
    description = "Documentation site";
    domain = "docs";
    environments = {
      dev = {
        env = {
          PORT = "ref+sops://.stackpanel/secrets/computed.yaml#/apps/docs/port";
        };
        name = "dev";
      };
      prod = {
        env = { };
        name = "prod";
      };
      staging = {
        env = { };
        name = "staging";
      };
    };
    linting = {
      oxlint = {
        enable = true;
      };
    };
    name = "docs";
    path = "apps/docs";
    type = "bun";
  };
  stackpanel-go = {
    description = "Stackpanel CLI and agent (Go)";
    environments = {
      dev = {
        env = {
          STACKPANEL_TEST_PAIRING_TOKEN = "token123";
        };
        name = "dev";
      };
    };
    name = "stackpanel";
    path = "apps/stackpanel-go";
    type = "go";
  };
  web = {
    commands = {
      dev = {
        command = "bun run -F web dev";
      };
    };
    description = "Main web application";
    domain = "stackpanel";
    environments = {
      dev = {
        env = {
          APP_HOST = "ref+sops://.stackpanel/secrets/computed.yaml#/apps/web/url";
          MEMO_MEMOAS_AD = "foobar";
          OPENAI_API_KEY = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/OPENAI_API_KEY";
          PORT = "ref+sops://.stackpanel/secrets/computed.yaml#/apps/web/port";
          POSTGRES_URL = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/DATABASE_URL";
        };
        name = "dev";
      };
      prod = {
        env = {
          OPENAI_API_KEY = "ref+sops://.stackpanel/secrets/groups/dev.yaml#/OPENAI_API_KEY";
        };
        name = "prod";
      };
    };
    linting = {
      oxlint = {
        fix = true;
      };
    };
    name = "web";
    path = "apps/web";
    type = "bun";
  };
}
