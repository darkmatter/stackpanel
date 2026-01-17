"use client";

import { cn } from "@/lib/utils";
import { AnimatePresence, LayoutGroup, motion } from "motion/react";
import React, { useEffect, useState } from "react";

export function TextAnimationTypewriterEffect() {
	return (
		<div className="p-4">
			<h1 className="text-left text-2xl font-bold tracking-tighter text-neutral-800 md:text-7xl dark:text-neutral-200">
				Build awesome websites <br /> with
				<TypewriterEffect
					words={["Next.js", "Tailwind CSS", "Motion", "Typescript", "React"]}
					typingSpeed={80}
					duration={800}
					deletingSpeed={75}
				/>
			</h1>
			<p className="mt-4 max-w-2xl text-lg text-neutral-600 dark:text-neutral-400">
				Create stunning animated text effects with our typewriter component.
				Perfect for landing pages, portfolios, and interactive experiences.
			</p>
			<div className="mt-8 flex flex-col gap-4 sm:flex-row">
				<motion.button
					whileHover={{ scale: 1.05 }}
					whileTap={{ scale: 0.95 }}
					className="rounded-lg bg-neutral-900 px-6 py-3 font-medium text-white transition-colors hover:bg-neutral-800 dark:bg-neutral-100 dark:text-neutral-900 dark:hover:bg-neutral-200"
				>
					Get Started
					<motion.span
						className="ml-2 inline-block"
						animate={{ x: [0, 4, 0] }}
						transition={{ repeat: Infinity, duration: 1.5 }}
					>
						→
					</motion.span>
				</motion.button>
				<motion.button
					whileHover={{ scale: 1.05 }}
					whileTap={{ scale: 0.95 }}
					className="rounded-lg border border-neutral-300 px-6 py-3 font-medium text-neutral-900 transition-colors hover:bg-neutral-100 dark:border-neutral-700 dark:text-neutral-100 dark:hover:bg-neutral-800"
				>
					<motion.span
						className="inline-block"
						animate={{ rotate: [0, 360] }}
						transition={{ repeat: Infinity, duration: 5, ease: "linear" }}
					>
						✨
					</motion.span>
					<span className="ml-2">View Examples</span>
				</motion.button>
			</div>
		</div>
	);
}

export function TypewriterEffect({
	words,
	className,
	typingSpeed = 50,
	duration = 800,
	deletingSpeed = 75,
}: {
	words: string[];
	className?: string;
	typingSpeed?: number;
	duration?: number;
	deletingSpeed?: number;
}) {
	const [currentWord, setCurrentWord] = useState("");
	const [currentIndex, setCurrentIndex] = useState(0);
	const [charIndex, setCharIndex] = useState(0);
	const [isDeleting, setIsDeleting] = useState(false);
	const [currentSpeed, setCurrentSpeed] = useState(typingSpeed);

	useEffect(() => {
		const timeout = setTimeout(() => {
			const word = words[currentIndex];

			if (!isDeleting) {
				setCurrentWord(word.substring(0, charIndex + 1));
				setCharIndex(charIndex + 1);

				if (charIndex >= word.length) {
					setIsDeleting(true);
					setCurrentSpeed(duration);
				}
			} else {
				setCurrentWord(word.substring(0, charIndex - 1));
				setCharIndex(charIndex - 1);
				setCurrentSpeed(deletingSpeed);

				if (charIndex <= 1) {
					setIsDeleting(false);
					setCurrentIndex((currentIndex + 1) % words.length);
					setCurrentSpeed(typingSpeed);
				}
			}
		}, currentSpeed);

		return () => clearTimeout(timeout);
	}, [
		currentWord,
		charIndex,
		currentIndex,
		isDeleting,
		currentSpeed,
		words,
		typingSpeed,
		duration,
		deletingSpeed,
	]);

	return (
		<span
			className={cn(
				"relative inline-block [perspective:1000px] [transform-style:preserve-3d]",
				className,
			)}
		>
			&nbsp;
			<LayoutGroup>
				<span>
					<AnimatePresence initial={false}>
						{currentWord.split("").map((char, index) => (
							<motion.span
								layout
								key={`${index}-${char}`}
								initial={{
									opacity: 0,
									y: 20,
									rotateY: 90,
									rotateX: 10,
									filter: "blur(10px)",
								}}
								animate={{
									opacity: 1,
									y: 0,
									rotateY: 0,
									rotateX: 0,
									filter: "blur(0px)",
								}}
								transition={{ duration: 0.2 }}
								className="inline-block"
							>
								{char}
							</motion.span>
						))}
					</AnimatePresence>
				</span>
				<motion.span
					layoutId="cursor"
					className="absolute inline-block w-[3px] rounded-full bg-gradient-to-b from-neutral-700 via-neutral-900 to-neutral-700 dark:from-neutral-400 dark:via-neutral-100 dark:to-neutral-400"
					style={{
						height: "1em",
						bottom: "0.05em",
						marginLeft: "0.1em",
					}}
					animate={{
						opacity: [1, 0, 1],
					}}
					transition={{
						duration: 0.1,
						opacity: {
							duration: 0.8,
							repeat: Infinity,
							repeatType: "loop",
							ease: "linear",
						},
					}}
				/>
			</LayoutGroup>
			&nbsp;
		</span>
	);
}
