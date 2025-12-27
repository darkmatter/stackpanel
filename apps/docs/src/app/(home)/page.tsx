import { BookOpen, Box, Code2, GitBranch, Lock, Network, Server, Terminal } from "lucide-react";
import Image from "next/image";
import Link from "next/link";

const features = [
  {
    icon: Terminal,
    title: "Reproducible Environments",
    description:
      "Nix-based dev shells that work identically across all machines. No more 'works on my machine'.",
  },
  {
    icon: Network,
    title: "Automatic Port Assignment",
    description:
      "Deterministic ports based on project name. Apps and services get consistent, conflict-free ports.",
  },
  {
    icon: Lock,
    title: "Secrets Management",
    description:
      "SOPS/vals integration with per-app schemas. Type-safe env access for TypeScript, Python, and Go.",
  },
  {
    icon: Server,
    title: "Service Orchestration",
    description:
      "PostgreSQL, Redis, Minio, and more. One command to start all your infrastructure.",
  },
  {
    icon: Code2,
    title: "IDE Integration",
    description: "VS Code workspace generation with JSON schema validation for YAML configs.",
  },
  {
    icon: GitBranch,
    title: "Multi-App Monorepos",
    description:
      "First-class support for monorepos with Caddy reverse proxy and per-app configuration.",
  },
];

export default function HomePage() {
  return (
    <main className="flex flex-1 flex-col">
      <section className="flex flex-col items-center justify-center gap-8 px-6 py-24 text-center md:py-32">
        <Image
          src="/dark.png"
          alt="StackPanel"
          width={240}
          height={80}
          className="dark:hidden"
          priority
        />
        <Image
          src="/light.png"
          alt="StackPanel"
          width={240}
          height={80}
          className="hidden dark:block"
          priority
        />
        <h1 className="max-w-3xl font-bold text-4xl leading-tight tracking-tight md:text-5xl">
          Development environments
          <br />
          <span className="text-fd-muted-foreground">that just work.</span>
        </h1>
        <p className="max-w-2xl text-fd-muted-foreground text-lg">
          StackPanel is a Nix-based framework for reproducible dev environments. Automatic ports,
          secrets management, service orchestration, and IDE integration — all configured in one
          place.
        </p>
        <div className="flex flex-wrap justify-center gap-4">
          <Link
            href="/docs"
            className="inline-flex items-center gap-2 rounded-lg bg-fd-primary px-6 py-3 font-medium text-fd-primary-foreground transition-colors hover:bg-fd-primary/90"
          >
            <BookOpen className="h-4 w-4" />
            Get Started
          </Link>
          <Link
            href="/docs/reference"
            className="inline-flex items-center gap-2 rounded-lg border border-fd-border bg-fd-background px-6 py-3 font-medium transition-colors hover:bg-fd-accent"
          >
            <Box className="h-4 w-4" />
            Reference
          </Link>
        </div>
      </section>

      <section className="border-fd-border border-t bg-fd-card/50 px-6 py-16">
        <div className="mx-auto max-w-5xl">
          <h2 className="mb-12 text-center font-semibold text-2xl">
            Everything you need for local development
          </h2>
          <div className="grid gap-8 md:grid-cols-2 lg:grid-cols-3">
            {features.map((feature) => (
              <div key={feature.title} className="flex flex-col gap-3">
                <div className="flex h-10 w-10 items-center justify-center rounded-lg bg-fd-primary/10">
                  <feature.icon className="h-5 w-5 text-fd-primary" />
                </div>
                <h3 className="font-semibold">{feature.title}</h3>
                <p className="text-fd-muted-foreground text-sm leading-relaxed">
                  {feature.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </section>

      <section className="px-6 py-16">
        <div className="mx-auto max-w-3xl">
          <h2 className="mb-6 text-center font-semibold text-2xl">Quick Start</h2>
          <div className="overflow-hidden rounded-lg border border-fd-border bg-fd-card">
            <div className="flex items-center gap-2 border-fd-border border-b bg-fd-muted/50 px-4 py-2">
              <div className="h-3 w-3 rounded-full bg-red-500/80" />
              <div className="h-3 w-3 rounded-full bg-yellow-500/80" />
              <div className="h-3 w-3 rounded-full bg-green-500/80" />
              <span className="ml-2 text-fd-muted-foreground text-xs">devenv.yaml</span>
            </div>
            <pre className="overflow-x-auto p-4 font-mono text-sm">
              <code>{`inputs:
  stackpanel:
    url: github:darkmatter/stackpanel

imports:
  - stackpanel`}</code>
            </pre>
          </div>
          <p className="mt-4 text-center text-fd-muted-foreground text-sm">
            Then run{" "}
            <code className="rounded bg-fd-muted px-1.5 py-0.5 font-mono text-xs">
              direnv allow
            </code>{" "}
            and you're ready to go.
          </p>
        </div>
      </section>
    </main>
  );
}
