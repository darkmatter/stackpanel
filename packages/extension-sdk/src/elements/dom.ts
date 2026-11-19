// The helpers (and element constructors) are evaluated only during registration or upgrade.
export function panelShadow(host: HTMLElement, css: string, ...children: Node[]) {
  const root = host.attachShadow({ mode: "open" });
  const style = host.ownerDocument.createElement("style");
  style.textContent = `:host { display: block; color: var(--foreground, inherit); font-family: var(--font-sans, inherit); }
    button, select { font: inherit; color: var(--foreground, ButtonText); background: var(--secondary, ButtonFace); border: 1px solid var(--input, ButtonBorder); border-radius: var(--radius, .3rem); padding: .3em .65em; }
    :focus-visible { outline: 2px solid var(--ring, Highlight); outline-offset: 2px; }
    [hidden] { display: none !important; }
    ${css}`;
  root.append(style, ...children);
}

/** A property set before customElements.define otherwise shadows its setter forever. */
export function upgradeProperties(host: HTMLElement, names: readonly string[]) {
  for (const name of names) {
    if (!Object.hasOwn(host, name)) continue;
    const value: unknown = Reflect.get(host, name);
    if (Reflect.deleteProperty(host, name)) Reflect.set(host, name, value);
  }
}
