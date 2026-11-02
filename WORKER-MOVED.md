# The Cloudflare Worker moved out of this repo

`worker` was extracted on 2026-08-23 to:

    ~/websites/*AUTOMATIONS/automation-focusguard-dns

Every Cloudflare Worker now lives in `~/websites/*AUTOMATIONS/`, one folder per
deployed worker, named after the worker itself. Deploy with `wrangler deploy` from
that folder.

Its history up to this point is still in this repo at commit `00d1609`, under the old
path. Nothing in this repo's build depends on it.
