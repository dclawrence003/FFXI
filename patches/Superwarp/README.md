# Superwarp participant-discovery candidate

Superwarp is by Akaden of Asura, with the contributors credited in the
upstream project.  This is a modification of its sendall helper, not an
original addon.  The included LICENSE preserves the full BSD notice from
the installed upstream superwarp.lua.  Upstream:
https://github.com/AkadenTK/superwarp

candidate/sendall.lua includes a fixed participant-discovery wait intended
to avoid ending a multi-client scan during a brief gap between replies.
It is preserved here for review.  This setup pass has not established its
behavior in the game or deployed it.  Review its complete diff against the
matching upstream version before installation.

Local changes were designed and directed by Don Lawrence, with code developed
using OpenAI Codex.  This credit does not replace upstream authorship.
