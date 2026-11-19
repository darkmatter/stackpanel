# Studio uses safe identifiers for object keys and public-state references.
id:
builtins.isString id
&& !(builtins.hasContext id)
&& builtins.match "[A-Za-z0-9_][A-Za-z0-9_.-]{0,127}" id != null
&& !(builtins.elem id [
  "prototype"
  "constructor"
  "__proto__"
  "__defineGetter__"
  "__defineSetter__"
  "__lookupGetter__"
  "__lookupSetter__"
  "hasOwnProperty"
  "isPrototypeOf"
  "propertyIsEnumerable"
  "toLocaleString"
  "toString"
  "valueOf"
])
