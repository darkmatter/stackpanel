import { notFound } from "next/navigation";
import { getPageImage, source } from "@/lib/source";

export const revalidate = false;

export async function GET(
	req: Request,
	{ params }: RouteContext<"/og/docs/[...slug]">,
) {
	const { slug } = await params;
	const page = source.getPage(slug.slice(0, -1));
	if (!page) notFound();

	return Response.redirect(new URL("/light.png", req.url), 307);
}

export function generateStaticParams() {
	return source.getPages().map((page) => ({
		lang: page.locale,
		slug: getPageImage(page).segments,
	}));
}
