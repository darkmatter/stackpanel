import { ArrowRight } from "lucide-react";
import { Button } from "@/components/ui/button";

export function CTASection() {
  return (
    <section className="border-border border-b">
      <div className="mx-auto max-w-7xl px-4 py-24 sm:px-6 lg:px-8">
        <div className="relative overflow-hidden rounded-2xl border border-border bg-card">
          <div className="absolute inset-0 bg-[radial-gradient(ellipse_at_center,_var(--tw-gradient-stops))] from-accent/10 via-transparent to-transparent" />

          <div className="relative px-6 py-16 text-center sm:px-12 sm:py-24">
            <h2 className="text-balance font-bold text-3xl text-foreground sm:text-4xl">
              Ready to own your infrastructure?
            </h2>
            <p className="mx-auto mt-4 max-w-xl text-pretty text-muted-foreground">
              Stop paying per seat. Stop dealing with vendor lock-in. Start with
              a platform that grows with your team.
            </p>

            <div className="mt-8 flex flex-wrap justify-center gap-4">
              <Button
                className="bg-foreground text-background hover:bg-foreground/90"
                size="lg"
              >
                Get Started <ArrowRight className="ml-2 h-4 w-4" />
              </Button>
              <Button size="lg" variant="outline">
                Talk to Sales
              </Button>
            </div>

            <p className="mt-8 text-muted-foreground text-sm">
              No credit card required · 14-day free trial · Cancel anytime
            </p>
          </div>
        </div>
      </div>
    </section>
  );
}
