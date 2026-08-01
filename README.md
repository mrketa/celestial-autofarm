# Celestial Autofarm

Matcha loader for the World 3 autofarm and serialized event collectors.

World 3 currently includes Stage 1, Stage 5, Stage 6, and experimental Stage 7 routes. Stage 7 uses live tsunami timing and automatic character-reset recovery; keep an eye on its first runs after game updates.

Event collection supports Summer Coins, Coin Battle coins, and Disco keys without running competing movement workers.

The bundled Skeet-style menu opens with `Delete`/`Entf`.

```lua
loadstring(game:HttpGet(
    "https://raw.githubusercontent.com/mrketa/celestial-autofarm/main/autofarm.lua"
))()
```

The loader follows the latest version on `main`. Only run remote Lua code from a repository you control and inspect changes before execution.
