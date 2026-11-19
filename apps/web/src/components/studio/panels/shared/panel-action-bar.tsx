import type { JsonObject, JsonValue } from "@bufbuild/protobuf";
import { Button } from "@ui/button";
import { createContext, useContext, useState, type ReactNode } from "react";
import {
  ModuleActionRunnerDialog,
  useModuleActionRunner,
  type ModuleActionRunnerDialogProps,
} from "../../command-runner";
import { useModule, useModuleQueryScope } from "../modules/use-modules";
import { ActionArgumentsDialog, needsArgumentDialog } from "./action-arguments-dialog";
import { getModuleIconByName } from "./module-icons";
import { hasActionReview } from "./panel-data";
import type { ModuleAction } from "./panel-types";

type DataResult = (value: JsonValue | undefined) => void;
interface Invocation {
  id: string;
  action: ModuleAction;
  row?: JsonObject;
  onSuccess?: DataResult;
}

const ActionsContext = createContext<{
  actions: Record<string, ModuleAction>;
  enabled: boolean;
  choose: (invocation: Invocation) => void;
} | null>(null);

/** A panel and all its rows share the evaluated module lookup and one invocation dialog. */
export function PanelActionScope({
  moduleId,
  children,
}: {
  moduleId: string;
  children: ReactNode;
}) {
  const query = useModule(moduleId);
  const { start, unavailable } = useModuleActionRunner();
  const [prompt, setPrompt] = useState<Invocation | null>(null);
  const [run, setRun] = useState<ModuleActionRunnerDialogProps | null>(null);
  const module = query.data?.module;
  const actions = module?.id === moduleId ? module.actions : {};
  const canRun = !unavailable && module?.id === moduleId && module.enabled && !query.isError;

  function launch(invocation: Invocation, args: JsonObject) {
    setPrompt(null);
    setRun(
      start({
        moduleId,
        actionId: invocation.id,
        args,
        label: invocation.action.label || invocation.id,
        invalidates: invocation.action.invalidates,
        onSuccess: invocation.onSuccess,
        onClose: () => setRun(null),
      }),
    );
  }
  return (
    <ActionsContext.Provider
      value={{
        actions,
        enabled: canRun && !run && !prompt,
        choose(invocation) {
          if (needsArgumentDialog(invocation.action)) setPrompt(invocation);
          else launch(invocation, {});
        },
      }}
    >
      {children}
      {query.error && (
        <p role="alert" className="text-sm text-destructive">
          Unable to load module actions: {query.error.message}
        </p>
      )}
      {unavailable && <p className="text-sm text-muted-foreground">{unavailable}</p>}
      {prompt && (
        <ActionArgumentsDialog
          action={prompt.action}
          row={prompt.row}
          onClose={() => setPrompt(null)}
          onSubmit={(args) => {
            // A project reload can change or remove a capability while its form is open.
            if (canRun && actions[prompt.id] === prompt.action) launch(prompt, args);
            else setPrompt(null);
          }}
        />
      )}
      {run && <ModuleActionRunnerDialog {...run} />}
    </ActionsContext.Provider>
  );
}

export function ActionButtons({
  actionIds,
  row,
  dataAction,
  onData,
}: {
  actionIds?: readonly string[];
  row?: JsonObject;
  dataAction?: string | null;
  onData?: DataResult;
}) {
  const scope = useContext(ActionsContext);
  if (!scope) return null;
  const ids = new Set(actionIds ?? Object.keys(scope.actions));
  if (dataAction) ids.add(dataAction);
  if (!ids.size) return null;
  return (
    <div className="flex flex-wrap gap-2">
      {Array.from(ids, (id) => {
        const action = Object.hasOwn(scope.actions, id) ? scope.actions[id] : undefined;
        const isProvider = id === dataAction;
        const unavailable = !action
          ? `Undeclared action: ${id}`
          : !hasActionReview(action)
            ? `Incomplete action details: ${id}`
            : isProvider && action.outputMode !== "json"
              ? "A data action must use JSON output."
              : undefined;
        const Icon = getModuleIconByName(action?.icon || (isProvider ? "refresh-cw" : "play"));
        return (
          <Button
            key={id}
            type="button"
            variant="outline"
            size="sm"
            disabled={!scope.enabled || !!unavailable}
            title={unavailable ?? action?.description}
            onClick={() => {
              if (action && !unavailable)
                scope.choose({ id, action, row, onSuccess: isProvider ? onData : undefined });
            }}
          >
            <Icon aria-hidden="true" className="size-3.5" />
            {action?.label || id}
          </Button>
        );
      })}
    </div>
  );
}

/** Module drawer / route toolbar; only IDs declared on this module can run. */
export function PanelActionBar({
  moduleId,
  actionIds,
}: {
  moduleId: string;
  actionIds?: readonly string[];
}) {
  const scope = useModuleQueryScope();
  return (
    <PanelActionScope key={JSON.stringify([...scope, moduleId])} moduleId={moduleId}>
      <ActionButtons actionIds={actionIds} />
    </PanelActionScope>
  );
}
