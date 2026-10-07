import { stationIds } from "@/lib/data/stations";
import { StationDetail } from "./StationDetail";

export function generateStaticParams() {
  return stationIds.map((id) => ({ id }));
}

export default async function StationPage({ params }: PageProps<"/stations/[id]">) {
  const { id } = await params;
  return <StationDetail id={id} />;
}
