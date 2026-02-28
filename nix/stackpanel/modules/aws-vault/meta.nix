{
  id = "aws-vault";
  name = "AWS Vault";
  description = "AWS Vault integration for secure AWS credential management";
  category = "cloud";
  version = "1.0.0";
  icon = "aws";
  homepage = "https://github.com/99designs/aws-vault";
  author = "stackpanel";
  tags = [
    "aws"
    "credentials"
    "security"
    "cloud"
  ];
  requires = [ ];
  conflicts = [ ];
  features = {
    files = false;
    scripts = true;
    healthchecks = true;
    packages = true;
    services = false;
    secrets = false;
    tasks = false;
    appModule = false;
  };
  priority = 50;
  configBoilerplate = ''
    modules.aws-vault = {
      enable = true;
      profile = "default";
    };
  '';
}
