"""Tool registry. Drop a module in this folder (copy _template.py) and it's live.
Discovery skips _-prefixed modules. call() never raises — errors go back to the model."""
import importlib, pkgutil

_mods = {}
for _m in pkgutil.iter_modules(__path__):
    if not _m.name.startswith("_"):
        _mod = importlib.import_module(f"{__name__}.{_m.name}")
        _mods[_mod.NAME] = _mod

def schemas():
    return [{"type": "function", "function":
             {"name": m.NAME, "description": m.DESCRIPTION, "parameters": m.PARAMETERS}}
            for m in _mods.values()]

def listing():
    return [{"name": m.NAME, "description": m.DESCRIPTION,
             "permission": getattr(m, "PERMISSION", None)} for m in _mods.values()]

def call(name, args):
    mod = _mods.get(name)
    if mod is None:
        return f"error: unknown tool '{name}'. Available tools: {', '.join(_mods)}"
    try:
        return mod.run(**args)
    except Exception as e:
        return f"error: {e}"
