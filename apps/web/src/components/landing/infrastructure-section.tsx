import { BarChart3, Database, HardDrive, Lock, Network, Search } from "lucide-react";
import { Button } from "@/components/ui/button";

export function InfrastructureSection() {
  const services = [
    { icon: Search, name: "ELK Stack", description: "Full logging and search" },
    { icon: Database, name: "PostgreSQL", description: "Managed databases" },
    { icon: Network, name: "Load Balancers", description: "Scale-to-zero LBs" },
    { icon: HardDrive, name: "Object Storage", description: "S3-compatible" },
    {
      icon: BarChart3,
      name: "Monitoring",
      description: "Prometheus + Grafana",
    },
    { icon: Lock, name: "Vault", description: "Secrets management" },
  ];

  return (
    <section className="border-border border-b bg-secondary/20" id="infrastructure">
      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="grid gap-12 lg:grid-cols-2 lg:gap-16">
          <div>
            <p className="font-medium text-accent text-sm">Infrastructure</p>
            <h2 className="mt-4 text-balance font-bold text-3xl text-foreground sm:text-4xl">
              One-click deploy robust systems
            </h2>
            <p className="mt-4 text-pretty text-muted-foreground leading-relaxed">
              Deploy an entire ELK stack, a Kubernetes cluster, or a managed database
              with a single click. We manage the complexity so you can focus on
              building.
            </p>
            <p className="mt-4 text-pretty text-muted-foreground leading-relaxed">
              All services are self-hosted on your infrastructure. No data leaves your
              network, and costs scale linearly with actual usage.
            </p>

            <div className="mt-8">
              <Button className="bg-foreground text-background hover:bg-foreground/90">
                Explore Services
              </Button>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-4 sm:grid-cols-3">
            {services.map((service) => (
              <div
                className="group flex flex-col items-center justify-center rounded-xl border border-border bg-card p-6 text-center transition-all hover:border-accent/50"
                key={service.name}
              >
                <div className="flex h-12 w-12 items-center justify-center rounded-lg bg-secondary transition-colors group-hover:bg-accent/20">
                  <service.icon className="h-6 w-6 text-muted-foreground transition-colors group-hover:text-accent" />
                </div>
                <p className="mt-3 font-medium text-foreground text-sm">
                  {service.name}
                </p>
                <p className="mt-1 text-muted-foreground text-xs">
                  {service.description}
                </p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
}
