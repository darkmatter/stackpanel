"use client";

import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Textarea } from "@ui/textarea";
import {
	Check,
	ChevronDown,
	GripVertical,
	Plus,
	Trash2,
	X,
} from "lucide-react";
import { useState } from "react";
import { AppHeader } from "@/components/app-header";
import { AppSidebar } from "@/components/app-sidebar";

type Task = {
	id: string;
	name: string;
	description: string;
	defaultCommand: string;
};

const initialTasks: Task[] = [
	{
		id: "1",
		name: "build",
		description: "Build the application for production",
		defaultCommand: "next build",
	},
	{
		id: "2",
		name: "dev",
		description: "Start the development server",
		defaultCommand: "next dev",
	},
	{
		id: "3",
		name: "test",
		description: "Run tests",
		defaultCommand: "jest",
	},
	{
		id: "4",
		name: "lint",
		description: "Lint code",
		defaultCommand: "eslint .",
	},
	{
		id: "5",
		name: "type-check",
		description: "Check TypeScript types",
		defaultCommand: "tsc --noEmit",
	},
];

export default function TasksPage() {
	const [tasks, setTasks] = useState<Task[]>(initialTasks);
	const [editingId, setEditingId] = useState<string | null>(null);
	const [editingTask, setEditingTask] = useState<Task | null>(null);

	const startEdit = (task: Task) => {
		setEditingId(task.id);
		setEditingTask({ ...task });
	};

	const cancelEdit = () => {
		setEditingId(null);
		setEditingTask(null);
	};

	const saveEdit = () => {
		if (editingTask) {
			setTasks(tasks.map((t) => (t.id === editingTask.id ? editingTask : t)));
			setEditingId(null);
			setEditingTask(null);
		}
	};

	const addTask = () => {
		const newTask: Task = {
			id: Date.now().toString(),
			name: "",
			description: "",
			defaultCommand: "",
		};
		setTasks([...tasks, newTask]);
		startEdit(newTask);
	};

	const deleteTask = (id: string) => {
		setTasks(tasks.filter((t) => t.id !== id));
		if (editingId === id) {
			cancelEdit();
		}
	};

	return (
		<div className="flex h-screen bg-background">
			<AppSidebar />

			{/* Main Content */}
			<main className="flex-1 flex flex-col overflow-hidden">
				<AppHeader
					title="Tasks"
					subtitle="Define turbo.json tasks for your monorepo"
				/>

				{/* Content */}
				<div className="flex-1 overflow-auto p-6">
					<div className="max-w-4xl">
						{/* Page Header */}
						<div className="mb-6">
							<h2 className="text-2xl font-semibold mb-1">Tasks</h2>
							<p className="text-sm text-muted-foreground">
								Define turbo.json tasks that can be configured for each app.
								Each task has a default command that apps can override.
							</p>
						</div>

						{/* Tasks List */}
						<div className="space-y-2">
							{tasks.map((task, index) => {
								const isEditing = editingId === task.id;
								const currentTask =
									isEditing && editingTask ? editingTask : task;

								return (
									<div
										key={task.id}
										className="border border-border rounded-lg bg-card overflow-hidden hover:border-primary/50 transition-colors"
									>
										<div className="p-4">
											{isEditing ? (
												<div className="space-y-3">
													<div className="flex items-start gap-3">
														<GripVertical className="h-5 w-5 text-muted-foreground mt-2 flex-shrink-0" />
														<div className="flex-1 space-y-3">
															<div className="grid grid-cols-2 gap-3">
																<div>
																	<label className="text-xs font-medium text-muted-foreground mb-1.5 block">
																		Task Name
																	</label>
																	<Input
																		value={currentTask.name}
																		onChange={(e) =>
																			setEditingTask({
																				...currentTask,
																				name: e.target.value,
																			})
																		}
																		placeholder="build"
																		className="font-mono"
																	/>
																</div>
																<div>
																	<label className="text-xs font-medium text-muted-foreground mb-1.5 block">
																		Default Command
																	</label>
																	<Input
																		value={currentTask.defaultCommand}
																		onChange={(e) =>
																			setEditingTask({
																				...currentTask,
																				defaultCommand: e.target.value,
																			})
																		}
																		placeholder="next build"
																		className="font-mono"
																	/>
																</div>
															</div>
															<div>
																<label className="text-xs font-medium text-muted-foreground mb-1.5 block">
																	Description
																</label>
																<Textarea
																	value={currentTask.description}
																	onChange={(e) =>
																		setEditingTask({
																			...currentTask,
																			description: e.target.value,
																		})
																	}
																	placeholder="Describe what this task does..."
																	className="resize-none"
																	rows={2}
																/>
															</div>
														</div>
														<div className="flex gap-1 flex-shrink-0">
															<Button
																variant="ghost"
																size="icon"
																className="h-8 w-8"
																onClick={saveEdit}
															>
																<Check className="h-4 w-4 text-green-500" />
															</Button>
															<Button
																variant="ghost"
																size="icon"
																className="h-8 w-8"
																onClick={cancelEdit}
															>
																<X className="h-4 w-4 text-destructive" />
															</Button>
														</div>
													</div>
												</div>
											) : (
												<div className="flex items-start gap-3">
													<GripVertical className="h-5 w-5 text-muted-foreground mt-0.5 flex-shrink-0" />
													<div className="flex-1 min-w-0">
														<div className="flex items-baseline gap-3 mb-1">
															<h3 className="text-sm font-semibold font-mono">
																{task.name}
															</h3>
															<code className="text-xs text-muted-foreground font-mono truncate">
																{task.defaultCommand}
															</code>
														</div>
														<p className="text-sm text-muted-foreground">
															{task.description}
														</p>
													</div>
													<div className="flex gap-1 flex-shrink-0">
														<Button
															variant="ghost"
															size="icon"
															className="h-8 w-8"
															onClick={() => startEdit(task)}
														>
															<Plus className="h-4 w-4" />
														</Button>
														<Button
															variant="ghost"
															size="icon"
															className="h-8 w-8 text-destructive"
															onClick={() => deleteTask(task.id)}
														>
															<Trash2 className="h-4 w-4" />
														</Button>
													</div>
												</div>
											)}
										</div>
									</div>
								);
							})}

							{/* Add Task Button */}
							<button
								onClick={addTask}
								className="w-full p-4 border border-dashed border-border rounded-lg hover:border-primary hover:bg-primary/5 transition-colors flex items-center justify-center gap-2 text-muted-foreground hover:text-foreground"
							>
								<Plus className="h-4 w-4" />
								<span className="text-sm font-medium">Add Task</span>
							</button>
						</div>

						{/* Info Section */}
						<div className="mt-8 p-4 border border-blue-500/20 bg-blue-500/5 rounded-lg">
							<h4 className="text-sm font-medium text-blue-600 dark:text-blue-400 mb-2 flex items-center gap-2">
								<ChevronDown className="h-4 w-4" />
								How Tasks Work
							</h4>
							<ul className="text-sm text-muted-foreground space-y-1 ml-6 list-disc">
								<li>
									Tasks defined here are available to all apps in your monorepo
								</li>
								<li>
									Each task has a default command that apps inherit
									automatically
								</li>
								<li>
									Apps can override the default command with their own custom
									scripts
								</li>
								<li>
									Tasks are synchronized with your turbo.json configuration
								</li>
							</ul>
						</div>
					</div>
				</div>
			</main>
		</div>
	);
}
