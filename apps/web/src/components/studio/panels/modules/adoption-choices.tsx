import type { ModuleAdoptionOffer } from "@stackpanel/proto/agent/v1/module";
import { Button } from "@ui/button";

export interface AdoptionDecision {
  id: string;
  revision: string;
  answer: boolean | string | string[];
}

export function AdoptionChoices({ offers, decisions, onChange, disabled }: {
  offers: ModuleAdoptionOffer[];
  decisions: AdoptionDecision[];
  onChange: (next: AdoptionDecision[]) => void;
  disabled: boolean;
}) {
  if (!offers.length) return null;
  function decide(offer: ModuleAdoptionOffer, answer?: AdoptionDecision["answer"]) {
    const rest = decisions.filter((item) => item.id !== offer.id);
    onChange(answer === undefined ? rest : [...rest, { id: offer.id, revision: offer.revision, answer }]);
  }
  return <section className="space-y-3 text-sm">
    <h3 className="font-medium">Adoption offers</h3>
    <p className="text-muted-foreground">Optional. Leave an offer undecided to skip it. Changing an answer evaluates a new plan; nothing is saved until you enable the module.</p>
    {offers.map((offer) => {
      const answer = decisions.find((item) => item.id === offer.id && item.revision === offer.revision)?.answer;
      const label = offer.label || offer.id;
      return <fieldset key={`${offer.id}:${offer.revision}`} disabled={disabled || !offer.revision} className="space-y-1 rounded-md border p-2">
        <legend className="font-medium">{label}</legend>
        {offer.description && <p>{offer.description}</p>}
        {offer.reason && <p className="text-muted-foreground">{offer.reason}</p>}
        {offer.type === "bool" && <select aria-label={label} value={answer === undefined ? "skip" : String(answer)}
          onChange={({ target }) => decide(offer, target.value === "skip" ? undefined : target.value === "true")}>
          <option value="skip">Leave undecided</option><option value="true">Accept</option><option value="false">Decline</option>
        </select>}
        {offer.type === "select" && <select aria-label={label} value={offer.choices.findIndex((choice) => choice.value === answer)}
          onChange={({ target }) => decide(offer, offer.choices[Number(target.value)]?.value)}>
          <option value={-1}>Leave undecided</option>{offer.choices.map((choice, index) => <option value={index} key={choice.value}>{choice.label || choice.value}</option>)}
        </select>}
        {offer.type === "multiselect" && <div className="space-y-2">
          {offer.choices.map((choice) => <label key={choice.value} className="flex items-center gap-2">
            <input type="checkbox" checked={Array.isArray(answer) && answer.includes(choice.value)} onChange={({ target }) => {
              const previous = Array.isArray(answer) ? answer : [];
              decide(offer, target.checked ? [...previous, choice.value] : previous.filter((item) => item !== choice.value));
            }} />{choice.label || choice.value}</label>)}
          <p>{answer === undefined ? "Undecided" : Array.isArray(answer) && !answer.length ? "Declined" : "Choices selected"}</p>
          <Button size="sm" variant="outline" onClick={() => decide(offer)}>Leave undecided</Button>{" "}
          <Button size="sm" variant="outline" onClick={() => decide(offer, [])}>Decline all</Button>
        </div>}
        {!offer.revision || !["bool", "select", "multiselect"].includes(offer.type) ? <p>This agent cannot accept an answer for this offer.</p> : null}
      </fieldset>;
    })}
  </section>;
}
