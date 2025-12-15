export function StatsSection() {
	const stats = [
		{ value: "80%", label: "reduction in setup time" },
		{ value: "Zero", label: "vendor lock-in" },
		{ value: "10x", label: "faster onboarding" },
		{ value: "$0", label: "per-seat pricing" },
	];

	return (
		<section className="border-border border-b bg-secondary/30">
			<div className="mx-auto max-w-7xl px-4 py-16 sm:px-6 lg:px-8">
				<div className="grid grid-cols-2 gap-8 lg:grid-cols-4">
					{stats.map((stat) => (
						<div className="text-center" key={stat.label}>
							<p className="font-bold text-3xl text-foreground sm:text-4xl">
								{stat.value}
							</p>
							<p className="mt-2 text-muted-foreground text-sm">{stat.label}</p>
						</div>
					))}
				</div>
			</div>
		</section>
	);
}
