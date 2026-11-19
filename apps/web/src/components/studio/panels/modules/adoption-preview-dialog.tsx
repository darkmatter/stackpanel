import type { ModulePreviewDiff } from "@stackpanel/proto/agent/v1/module";
import { Button } from "@ui/button";
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from "@ui/dialog";
import { useState } from "react";
import { AdoptionChoices, type AdoptionDecision } from "./adoption-choices";
import { useEnableModule, useModule, useModulePreview } from "./use-modules";

function PlanSection({ label, diff }: { label: string; diff?: ModulePreviewDiff }) {
  if (!diff) return null;
  const groups = [
    { label: "Add", items: diff.added },
    { label: "Change", items: diff.changed },
    { label: "Remove", items: diff.removed },
  ];
  return (
    <section>
      <h3 className="font-medium">{label}</h3>
      {groups.every(({ items }) => !items.length) && (
        <p className="text-muted-foreground">No changes</p>
      )}
      {groups.map(
        ({ label: operation, items }) =>
          items.length > 0 && (
            <ul key={operation} aria-label={`${operation} ${label.toLowerCase()}`}>
              {items.map((item) => (
                <li key={item}>
                  {operation}: <code className="break-all">{item}</code>
                </li>
              ))}
            </ul>
          ),
      )}
    </section>
  );
}

/** Mount only while reviewing so reopening always evaluates a fresh plan. */
export function AdoptionPreviewDialog({
  moduleId,
  onClose,
  onEnabled,
}: {
  moduleId: string;
  onClose: () => void;
  onEnabled: (message: string) => void;
}) {
  const detail = useModule(moduleId);
  const enable = useEnableModule(moduleId);
  const needsEnable = detail.data?.module.enabled === false && !detail.error;
  const [decisions, setDecisions] = useState<AdoptionDecision[]>([]);
  const baseline = useModulePreview(moduleId, needsEnable && !enable.isPending);
  const selected = useModulePreview(
    moduleId,
    needsEnable && !enable.isPending && decisions.length > 0,
    decisions,
  );
  const preview = decisions.length ? selected : baseline;
  const offers = preview.data?.offers ?? baseline.data?.offers ?? [];
  const reviewed = decisions.every(({ id, revision }) =>
    preview.data?.offers.some((offer) => offer.id === id && offer.revision === revision),
  );
  return (
    <Dialog
      open
      onOpenChange={(open) => {
        if (!open && !enable.isPending) onClose();
      }}
    >
      <DialogContent className="max-h-[85vh] overflow-y-auto">
        <DialogHeader>
          <DialogTitle>Enable module?</DialogTitle>
          <DialogDescription>
            Review the changes evaluated for {moduleId} in this project before enabling it.
          </DialogDescription>
        </DialogHeader>
        {detail.error && (
          <p role="alert" className="text-destructive">
            Could not verify module state: {detail.error.message}
          </p>
        )}
        {detail.data?.module.enabled && !enable.isPending && <p>This module is already enabled.</p>}
        {preview.isFetching && <p role="status">Evaluating enable plan…</p>}
        {preview.error && (
          <div role="alert" className="space-y-2 text-destructive">
            <p>Could not preview changes: {preview.error.message}</p>
            <Button variant="outline" onClick={() => void preview.refetch()}>
              Retry preview
            </Button>
          </div>
        )}
        {needsEnable && preview.data && !preview.error && (
          <div className="space-y-4 text-sm">
            <PlanSection label="Files" diff={preview.data.files} />
            <PlanSection label="Packages" diff={preview.data.packages} />
            <PlanSection label="Services" diff={preview.data.services} />
            {!reviewed && (
              <p role="alert">
                An adoption offer changed. Discard your answers and review the current offers.
              </p>
            )}
          </div>
        )}
        {needsEnable && (
          <AdoptionChoices
            offers={offers}
            decisions={decisions}
            disabled={enable.isPending}
            onChange={(next) => {
              enable.reset();
              setDecisions(next);
            }}
          />
        )}
        {decisions.length > 0 && (preview.error || !reviewed) && !preview.isFetching && (
          <Button
            variant="outline"
            onClick={() => {
              setDecisions([]);
              void baseline.refetch();
            }}
          >
            Discard answers and refresh offers
          </Button>
        )}
        {enable.error && (
          <p role="alert" className="text-destructive">
            Enable failed: {enable.error.message}
          </p>
        )}
        <DialogFooter>
          <Button variant="outline" disabled={enable.isPending} onClick={onClose}>
            Cancel
          </Button>
          <Button
            title={enable.unavailable}
            disabled={
              !needsEnable ||
              !reviewed ||
              !preview.data ||
              preview.isFetching ||
              !!preview.error ||
              enable.isPending ||
              !!enable.unavailable
            }
            onClick={() =>
              enable.mutate(decisions, {
                onSuccess: ({ message }) => {
                  onEnabled(message || `Enabled ${moduleId}.`);
                  onClose();
                },
              })
            }
          >
            {enable.isPending ? "Enabling…" : "Enable"}
          </Button>
        </DialogFooter>
      </DialogContent>
    </Dialog>
  );
}
