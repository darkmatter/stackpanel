# ==============================================================================
# apps.nix
#
# Application definitions for the monorepo.
# Each app has embedded tasks and variables maps (matches proto App shape).
# ==============================================================================
{
  web = {
    name = "web";
    description = "Main web application (Next.js)";
    path = "apps/web";
    type = "bun";
    domain = "stackpanel";
    port = 3000;
    tasks = {
      dev = {
        key = "dev";
        description = "Start development server with hot reload";
        command = "bun run dev";
        env = { };
      };
      build = {
        key = "build";
        description = "Build for production";
        command = "bun run build";
        env = { };
      };
      test = {
        key = "test";
        description = "Run test suite";
        command = "bun run test";
        env = { };
      };
    };
    variables = {
      APP_URL = {
        key = "APP_URL";
        description = "Public application URL";
        type = "APP_VARIABLE_TYPE_LITERAL";
        value = "http://localhost:3000";
      };
      API_URL = {
        key = "API_URL";
        description = "Backend API URL";
        type = "APP_VARIABLE_TYPE_LITERAL";
        value = "http://localhost:3001";
      };
      AUTH_SECRET = {
        key = "AUTH_SECRET";
        description = "Secret key for session signing";
        type = "APP_VARIABLE_TYPE_VARIABLE";
        value = "AUTH_SECRET";
      };
      DATABASE_URL = {
        key = "DATABASE_URL";
        description = "PostgreSQL connection string";
        type = "APP_VARIABLE_TYPE_VARIABLE";
        value = "DATABASE_URL";
      };
    };
  };

  docs = {
    name = "docs";
    description = "Documentation site";
    path = "apps/docs";
    type = "bun";
    domain = "docs";
    port = 3002;
    tasks = {
      dev = {
        key = "dev";
        description = "Start documentation dev server";
        command = "bun run dev";
        env = { };
      };
      build = {
        key = "build";
        description = "Build documentation site";
        command = "bun run build";
        env = { };
      };
    };
    variables = {
      APP_URL = {
        key = "APP_URL";
        description = "Public docs URL";
        type = "APP_VARIABLE_TYPE_LITERAL";
        value = "http://localhost:3002";
      };
    };
  };

  server = {
    name = "server";
    description = "Backend API server";
    path = "apps/server";
    type = "bun";
    port = 3001;
    tasks = {
      dev = {
        key = "dev";
        description = "Start API server in development mode";
        command = "bun run dev";
        env = { };
      };
      build = {
        key = "build";
        description = "Build API server";
        command = "bun run build";
        env = { };
      };
      test = {
        key = "test";
        description = "Run API tests";
        command = "bun run test";
        env = { };
      };
    };
    variables = {
      DATABASE_URL = {
        key = "DATABASE_URL";
        description = "PostgreSQL connection string";
        type = "APP_VARIABLE_TYPE_VARIABLE";
        value = "DATABASE_URL";
      };
      REDIS_URL = {
        key = "REDIS_URL";
        description = "Redis connection string";
        type = "APP_VARIABLE_TYPE_VARIABLE";
        value = "REDIS_URL";
      };
      AUTH_SECRET = {
        key = "AUTH_SECRET";
        description = "Secret key for session signing";
        type = "APP_VARIABLE_TYPE_VARIABLE";
        value = "AUTH_SECRET";
      };
      STRIPE_SECRET_KEY = {
        key = "STRIPE_SECRET_KEY";
        description = "Stripe secret API key";
        type = "APP_VARIABLE_TYPE_VARIABLE";
        value = "STRIPE_SECRET_KEY";
      };
    };
  };

  stackpanel-go = {
    name = "stackpanel";
    description = "Stackpanel CLI and agent (Go)";
    path = "apps/stackpanel-go";
    type = "go";
    tasks = {
      build = {
        key = "build";
        description = "Build Go binary";
        command = "go build -o stackpanel ./cmd/stackpanel";
        env = { };
      };
      test = {
        key = "test";
        description = "Run Go tests";
        command = "go test ./...";
        env = { };
      };
    };
    variables = { };
  };
}
