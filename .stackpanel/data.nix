{
  binary-cache = {
    cachix = {
      cache = "darkmatter";
      enable = false;
    };
    enable = true;
  };
  deployment = {
    fly = {
      organization = "darkmatter";
    };
  };
  secrets = {
    backend = "chamber";
    codegen = {
      typescript = {
        directory = "packages/env/src/generated";
        language = "CODEGEN_LANGUAGE_TYPESCRIPT";
        name = "env";
      };
    };
    enable = true;
    environments = { };
    input-directory = ".stackpanel/secrets";
    secrets-dir = ".stackpanel/secrets/vars";
    system-keys = [ ];
  };
  sst = {
    account-id = "950224716579";
    config-path = "packages/infra/sst.config.ts";
    enable = true;
    iam = {
      role-name = "stackpanel-secrets-role";
    };
    kms = {
      alias = "stackpanel-secrets";
      deletion-window-days = 30;
      enable = true;
    };
    oidc = {
      flyio = {
        app-name = "*";
        org-id = "";
      };
      github-actions = {
        branch = "*";
        org = "darkmatter";
        repo = "stackpanel";
      };
      provider = "github-actions";
      roles-anywhere = {
        trust-anchor-arn = "";
      };
    };
    project-name = "stackpanel";
    region = "us-west-2";
  };
  variables = {
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
  };
}
