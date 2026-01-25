{
  docs = {
    description = "Documentation site";
    domain = "docs";
    environments = {
      dev = {
        env = { };
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
  server = {
    description = "Backend API server";
    name = "server";
    path = "apps/server";
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
          OPENAI_API_KEY = "ref+sops://.stackpanel/secrets/dev.yaml#/OPENAI_API_KEY";
          POSTGRES_URL = "ref+sops://.stackpanel/secrets/dev.yaml#/DATABASE_URL";
        };
        name = "dev";
      };
      prod = {
        env = {
          OPENAI_API_KEY = "ref+sops://.stackpanel/secrets/prod.yaml#/OPENAI_API_KEY";
        };
        name = "prod";
      };
    };
    name = "web";
    path = "apps/web";
    type = "bun";
  };
}

