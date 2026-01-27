import { cn } from "@stackpanel/ui-core";

interface CircularProgressProps {
  /** Progress value from 0 to 100 */
  value: number;
  /** Diameter of the circle in pixels */
  size?: number;
  /** Stroke width in pixels */
  strokeWidth?: number;
  /** Optional label to display in the center */
  label?: string;
  className?: string;
  trackClassName?: string;
  indicatorClassName?: string;
}

export function CircularProgress({
  value,
  size = 28,
  strokeWidth = 2.5,
  label,
  className,
  trackClassName,
  indicatorClassName,
}: CircularProgressProps) {
  const radius = (size - strokeWidth) / 2;
  const circumference = 2 * Math.PI * radius;
  const offset = circumference - (Math.min(Math.max(value, 0), 100) / 100) * circumference;

  return (
    <div
      className={cn("relative inline-flex items-center justify-center", className)}
      style={{ width: size, height: size }}
    >
      <svg
        width={size}
        height={size}
        viewBox={`0 0 ${size} ${size}`}
        className="-rotate-90"
      >
        {/* Background track */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          strokeWidth={strokeWidth}
          className={cn("stroke-primary/20", trackClassName)}
        />
        {/* Progress indicator */}
        <circle
          cx={size / 2}
          cy={size / 2}
          r={radius}
          fill="none"
          strokeWidth={strokeWidth}
          strokeDasharray={circumference}
          strokeDashoffset={offset}
          strokeLinecap="round"
          className={cn(
            "stroke-emerald-500 transition-[stroke-dashoffset] duration-300",
            indicatorClassName,
          )}
        />
      </svg>
      {label && (
        <span className="absolute inset-0 flex items-center justify-center text-[9px] font-medium leading-none">
          {label}
        </span>
      )}
    </div>
  );
}
