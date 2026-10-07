import { Suspense } from "react";
import { ReportForm } from "./ReportForm";

export default function ReportPage() {
  return (
    <Suspense>
      <ReportForm />
    </Suspense>
  );
}
