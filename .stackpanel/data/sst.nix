{
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
}

