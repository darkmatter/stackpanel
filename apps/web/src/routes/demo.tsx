import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/demo")({
  beforeLoad: () => {
    throw redirect({ to: "/studio", search: { demo: 1 }, replace: true });
  },
});
