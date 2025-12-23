import { GitBranch, Key, Layers, Server, Shield, Users } from "lucide-react";

export function FeaturesSection() {
  const features = [
    {
      icon: Server,
      title: "GitOps Infrastructure",
      description:
        "An internal repo that deploys your servers, load balancers, databases, and everything you need in production. We manage it for you.",
    },
    {
      icon: Shield,
      title: "Internal CA & mTLS",
      description:
        "Deploy an internal Certificate Authority. Issue certs to all machines and team members for zero-trust networking.",
    },
    {
      icon: Users,
      title: "SSO Authentication",
      description:
        "Built-in SSO auth system for frictionless team onboarding. Add team members in minutes, not days.",
    },
    {
      icon: Key,
      title: "Secrets Management",
      description:
        "Manage secrets using age encryption with your team members' public keys. Secure by default.",
    },
    {
      icon: GitBranch,
      title: "Tailscale Integration",
      description:
        "Private networking for your team out of the box. Share databases and services internally with zero friction.",
    },
    {
      icon: Layers,
      title: "Scale-to-Zero",
      description:
        "Load balancers and services that scale to zero when not in use. Only pay for what you actually need.",
    },
  ];

  return (
    <section className="border-border border-b" id="features">
      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="text-center">
          <p className="font-medium text-accent text-sm">Platform Features</p>
          <h2 className="mt-4 text-balance font-bold text-3xl text-foreground sm:text-4xl">
            Everything you need to ship
          </h2>
          <p className="mx-auto mt-4 max-w-2xl text-pretty text-muted-foreground">
            Self-hosted infrastructure that scales with your business. No per-seat
            pricing, no vendor lock-in, just powerful tools that work.
          </p>
        </div>

        <div className="mt-16 grid gap-8 sm:grid-cols-2 lg:grid-cols-3">
          {features.map((feature) => (
            <div
              className="group rounded-xl border border-border bg-card p-6 transition-all hover:border-accent/50 hover:bg-card/80"
              key={feature.title}
            >
              <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-accent/10 transition-colors group-hover:bg-accent/20">
                <feature.icon className="h-6 w-6 text-accent" />
              </div>
              <h3 className="mt-4 font-semibold text-foreground text-lg">
                {feature.title}
              </h3>
              <p className="mt-2 text-muted-foreground text-sm leading-relaxed">
                {feature.description}
              </p>
            </div>
          ))}
        </div>
      </div>
    </section>
  );
}
