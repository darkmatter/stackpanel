"use client";

import { ToggleGroup, ToggleGroupItem } from "@ui/toggle-group";
import { AlignCenterIcon, AlignLeftIcon, AlignRightIcon } from "lucide-react";

export const title = "Single Selection Toggle Group";

const Example = () => (
	<ToggleGroup type="single" variant="outline">
		<ToggleGroupItem aria-label="Align left" value="left">
			<AlignLeftIcon />
		</ToggleGroupItem>
		<ToggleGroupItem aria-label="Align center" value="center">
			<AlignCenterIcon />
		</ToggleGroupItem>
		<ToggleGroupItem aria-label="Align right" value="right">
			<AlignRightIcon />
		</ToggleGroupItem>
	</ToggleGroup>
);

export default Example;
