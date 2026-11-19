import type { RegistryModule } from "@stackpanel/proto/agent/v1/module";
import { Badge } from "@ui/badge";
import { Button } from "@ui/button";
import { Input } from "@ui/input";
import { Sheet, SheetContent, SheetDescription, SheetHeader, SheetTitle } from "@ui/sheet";
import { useState } from "react";
import { ModuleMarkdown } from "../shared/module-markdown";
import { AdoptionPreviewDialog } from "./adoption-preview-dialog";
import { ModuleEnableControl, ShellRebuildPrompt } from "./module-lifecycle-controls";
import { getCategoryLabel } from "./module-labels";
import {
  useInstallModule,
  useModule,
  useRegistryModule,
  useUninstallModule,
  useUpdateModule,
} from "./use-modules";
import { ModuleDetailDrawer } from "./module-detail-drawer";

import { ManualFlakeSetup } from "./manual-flake-setup";

function RegistryLifecycle({
  entry,
  onConfigure,
}: {
  entry: RegistryModule;
  onConfigure: (id: string) => void;
}) {
  const [version, setVersion] = useState(entry.latestVersion);
  const [ref, setRef] = useState("");
  const [message, setMessage] = useState("");
  const [review, setReview] = useState(false);
  const [confirmRemove, setConfirmRemove] = useState(false);
  const install = useInstallModule();
  const update = useUpdateModule();
  const uninstall = useUninstallModule();
  const moduleId = entry.slug;
  const detail = useModule(moduleId, { enabled: entry.installed });
  const selected = entry.versions.find((item) => item.version === version);
  const request = { moduleId, version, ref: ref.trim() };
  const pending = install.isPending || update.isPending || uninstall.isPending;
  const error = install.error || update.error || uninstall.error;
  function resetStatus() {
    install.reset();
    update.reset();
    uninstall.reset();
    setConfirmRemove(false);
    setMessage("");
  }
  return (
    <div className="space-y-4">
      <div className="flex flex-wrap items-center gap-2">
        <Badge variant={entry.installed ? "default" : "outline"}>
          {entry.installed ? "Installed" : "Not installed"}
        </Badge>
        {entry.installed && (
          <span className="text-sm text-muted-foreground">
            {entry.installedVersion
              ? `Locked version: ${entry.installedVersion}`
              : "Lock does not identify a catalog version"}
          </span>
        )}
      </div>
      <div className="grid gap-3 sm:grid-cols-2">
        <label className="space-y-1 text-sm">
          <span>Version</span>
          <select
            aria-label="Version"
            className="h-9 w-full rounded-md border bg-background px-2"
            disabled={pending}
            value={version}
            onChange={(event) => setVersion(event.target.value)}
          >
            {entry.versions.map((item) => (
              <option key={item.version} value={item.version}>
                {item.version}
                {item.version === entry.latestVersion ? " (latest)" : ""}
              </option>
            ))}
          </select>
        </label>
        <label className="space-y-1 text-sm">
          <span>Git ref (optional override)</span>
          <Input
            aria-label="Git ref"
            placeholder={selected?.ref || "Branch, tag or revision"}
            disabled={pending}
            value={ref}
            onChange={(event) => setRef(event.target.value)}
          />
        </label>
      </div>
      <div className="flex flex-wrap gap-2">
        {entry.installed ? (
          <>
            <Button
              title={update.unavailable}
              disabled={pending || !selected || !!update.unavailable}
              onClick={() => {
                resetStatus();
                update.mutate(request, {
                  onSuccess: (response) => setMessage(response.message || `Updated ${moduleId}.`),
                });
              }}
            >
              {update.isPending ? "Updating…" : "Update"}
            </Button>
            <Button
              variant="outline"
              title={uninstall.unavailable}
              disabled={pending || !!uninstall.unavailable}
              onClick={() => {
                resetStatus();
                setConfirmRemove(true);
              }}
            >
              Uninstall
            </Button>
          </>
        ) : (
          <Button
            title={install.unavailable}
            disabled={pending || !selected || !!install.unavailable}
            onClick={() => {
              resetStatus();
              install.mutate(request, {
                onSuccess: (response) => {
                  setMessage(response.message || `Installed ${moduleId}.`);
                  setReview(true);
                },
              });
            }}
          >
            {install.isPending ? "Installing…" : "Install"}
          </Button>
        )}
        {entry.installed && detail.data && !detail.error && !pending && (
          <ModuleEnableControl
            moduleId={detail.data.module.id}
            enabled={detail.data.module.enabled}
            onChanged={setMessage}
          />
        )}
        {entry.installed && detail.data && !detail.error && (
          <Button
            variant="outline"
            disabled={pending}
            onClick={() => onConfigure(detail.data.module.id)}
          >
            Configure module
          </Button>
        )}
      </div>
      {confirmRemove && (
        <div className="space-y-2 rounded-md border p-3 text-sm">
          <p>Remove the {moduleId} input and its module import from this project?</p>
          <div className="flex gap-2">
            <Button
              variant="destructive"
              disabled={pending}
              onClick={() => {
                uninstall.mutate(moduleId, {
                  onSuccess: (response) => {
                    setConfirmRemove(false);
                    setReview(false);
                    setMessage(response.message || `Uninstalled ${moduleId}.`);
                  },
                });
              }}
            >
              {uninstall.isPending ? "Uninstalling…" : "Confirm uninstall"}
            </Button>
            <Button variant="outline" disabled={pending} onClick={() => setConfirmRemove(false)}>
              Cancel
            </Button>
          </div>
        </div>
      )}
      {error && (
        <p role="alert" className="text-sm text-destructive">
          {error.message}
        </p>
      )}
      {entry.installed && detail.error && (
        <div className="space-y-2">
          <p role="alert" className="text-sm text-destructive">
            Could not read the installed module: {detail.error.message}
          </p>
          <Button variant="outline" onClick={() => void detail.refetch()}>
            Retry module lookup
          </Button>
        </div>
      )}
      {review && entry.installed && !detail.error && (
        <AdoptionPreviewDialog
          moduleId={moduleId}
          onClose={() => setReview(false)}
          onEnabled={setMessage}
        />
      )}
      {message && <ShellRebuildPrompt key={message} message={message} />}
      {selected && <ManualFlakeSetup slug={moduleId} release={selected} override={ref.trim()} />}
    </div>
  );
}

export function RegistryModuleDrawer({
  moduleId,
  open,
  onOpenChange,
}: {
  moduleId: string;
  open: boolean;
  onOpenChange: (open: boolean) => void;
}) {
  const { data, error, refetch } = useRegistryModule(open ? moduleId : "");
  const [configure, setConfigure] = useState("");
  if (configure)
    return <ModuleDetailDrawer moduleId={configure} open={open} onOpenChange={onOpenChange} />;
  return (
    <Sheet open={open} onOpenChange={onOpenChange}>
      <SheetContent className="w-full space-y-6 overflow-y-auto px-4 sm:max-w-xl">
        <SheetHeader>
          <SheetTitle>{data?.module.name || moduleId}</SheetTitle>
          <SheetDescription>
            {data?.module.description || "Registry module details"}
          </SheetDescription>
        </SheetHeader>
        {error ? (
          <div className="space-y-2">
            <p role="alert" className="text-destructive">
              Could not load module: {error.message}
            </p>
            <Button variant="outline" onClick={() => void refetch()}>
              Try again
            </Button>
          </div>
        ) : !data ? (
          <p role="status">Loading module…</p>
        ) : (
          <>
            <div className="flex flex-wrap gap-2">
              <Badge variant="outline">{getCategoryLabel(data.module.category)}</Badge>
              {data.module.tier && <Badge variant="secondary">{data.module.tier}</Badge>}
              {data.module.tags.map((tag) => (
                <Badge key={tag} variant="outline">
                  {tag}
                </Badge>
              ))}
            </div>
            <RegistryLifecycle key={moduleId} entry={data.module} onConfigure={setConfigure} />
            {!!data.module.features.length && (
              <section>
                <h3 className="font-medium">Features</h3>
                <p className="text-sm">{data.module.features.join(", ")}</p>
              </section>
            )}
            {data.readme && (
              <section>
                <h3 className="mb-2 font-medium">README</h3>
                <ModuleMarkdown>{data.readme}</ModuleMarkdown>
              </section>
            )}
          </>
        )}
      </SheetContent>
    </Sheet>
  );
}
