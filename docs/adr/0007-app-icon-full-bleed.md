# ADR-0007: A full-bleed app icon, so the Signer tile matches the other wallet apps

- Status: Accepted
- Date: 2026-11-23
- Scope: `evm_signer_ui` — `src/icons/signer.png` only. Asset change, no code.

## Context

Basecamp masks app tiles to its own rounded shape on the home grid and in the catalog. An app icon
is meant to be **full-bleed**: paint the field edge-to-edge and let Basecamp round it (the icon
contract, manifest `>= 0.4.0` with a 256x256 `assets/icon.png`).

The Signer icon did not do this. It was authored the old way: a navy rounded-rect "squircle" with
its own baked corner radius, drawn on a **transparent** canvas (its corners sampled `(0,0,0,0)`). So
on a masked tile it rounded a second time and floated inset, a rounded-rect inside a rounded tile,
with a visible margin gap. Next to the Keycard app, whose icon is full-bleed (opaque to the edge),
the two read as different icon systems.

## Decision

Re-author `signer.png` as full-bleed: the blue keyhole glyph, unchanged in shape and position, on a
field that is **opaque to the edges**, and let Basecamp apply the tile shape. The field is solid
black `(0,0,0)`, matching the Keycard app's icon so the wallet apps share one look.

- Glyph unchanged: the same keyhole (blue `#4f9cf5`), extracted from the previous icon.
- Corners now `(0,0,0,255)` instead of `(0,0,0,0)`; no baked squircle, no transparent margin.
- 256x256 RGBA, as before.

Keeping the blue-on-navy identity by using a full-bleed **navy** field instead of black was the
alternative; black was chosen for consistency with the Keycard tile.

## Consequences

Positive:

- The Signer tile fills its tile and is masked to the same shape as the other wallet apps; no inset
  float, no double rounding.
- One field colour across Keycard and Signer, so the wallet apps read as a set.

Costs:

- The icon no longer carries its own navy background; it now depends on Basecamp's tile shape, which
  is the point of the full-bleed contract.

## Verification

Installed into a running Basecamp and viewed on the home grid (2026-11-23): the Signer tile shows the
blue keyhole on a full-bleed black field, masked to the same rounded shape as the Keycard tile, with
no margin gap. Corner pixels of the asset are opaque `(0,0,0,255)`.
