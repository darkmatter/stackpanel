# aws/

AWS infrastructure module - IAM, S3, Lambda, and other AWS resources.

## Files

| File | Purpose |
|------|---------|
| `default.nix` | Module entrypoint (scaffold) |

## Planned Options

```nix
stackpanel.aws = {
  enable = true;
  region = "us-west-2";

  # IAM
  iam = {
    roles = { /* ... */ };
    policies = { /* ... */ };
  };

  # S3
  s3 = {
    buckets = {
      assets = { acl = "private"; };
    };
  };

  # Lambda
  lambda = {
    functions = {
      api = {
        handler = "index.handler";
        runtime = "nodejs20.x";
      };
    };
  };

  # Secrets Manager integration
  secretsManager = {
    enable = true;
    # Sync with stackpanel.secrets
  };
};
```

## Generated Files

- Terraform configurations
- alchemy.run configurations
- AWS CDK stacks (optional)
- GitHub Actions for deployment

## TODO

- [ ] Basic IAM role/policy generation
- [ ] S3 bucket configuration
- [ ] Lambda function deployment
- [ ] Secrets Manager sync with agenix
- [ ] VPC configuration
- [ ] RDS/Aurora setup
- [ ] CloudFront CDN
- [ ] Route53 DNS
