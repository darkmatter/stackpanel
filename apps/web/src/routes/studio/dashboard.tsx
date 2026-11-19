import { createFileRoute, redirect } from "@tanstack/react-router";

export const Route = createFileRoute("/studio/dashboard")({
  beforeLoad: ({ search }) => {
    throw redirect({ to: "/studio", search, replace: true });
  },
});
