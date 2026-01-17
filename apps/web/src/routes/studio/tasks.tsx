import { createFileRoute } from "@tanstack/react-router";
import { TasksPanel } from "@/components/studio/panels/tasks-panel";

export const Route = createFileRoute("/studio/tasks")({
	component: TasksRoute,
});

function TasksRoute() {
	return <TasksPanel />;
}
