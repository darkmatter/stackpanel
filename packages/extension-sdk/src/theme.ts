import { THEME_KEYS, type ThemeTokens } from "./protocol.js";

/** Restore only inline properties that we overrode; the panel owns the rest of its CSS. */
export function createThemeSync(frame: Window) {
  const previous = new Map<string, { value: string; priority: string }>();
  return (tokens: ThemeTokens) => {
    const style = frame.document.documentElement.style;
    for (const key of THEME_KEYS) {
      const value = tokens[key];
      if (typeof value === "string" && value !== "") {
        if (!previous.has(key)) {
          previous.set(key, {
            value: style.getPropertyValue(key),
            priority: style.getPropertyPriority(key),
          });
        }
        style.setProperty(key, value);
      } else {
        const original = previous.get(key);
        if (!original) continue;
        style.setProperty(key, original.value, original.priority);
        previous.delete(key);
      }
    }
  };
}
