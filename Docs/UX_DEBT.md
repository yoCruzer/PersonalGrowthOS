# UX Debt

| ID | Priority | Area | Observation | Status | V1 treatment |
| --- | --- | --- | --- | --- | --- |
| UX-01 | P2 | Entry media | Landscape and portrait images shared a portrait-biased container, leaving conspicuous gray side space for landscape images. | RESOLVED — Build 5 candidate | The shared presentation now preserves each image's aspect ratio, removes the forced gray container, and caps only maximum height. Targeted aspect-ratio/media validation and Debug build passed. |
| UX-02 | P2 | Entry media | Images could not be opened in a larger or full-screen preview. | RESOLVED — Build 5 candidate | Entry-detail images now open a lightweight full-screen, aspect-fit preview with a clear close control and thumbnail fallback; no media-browser or editor scope was added. Targeted media validation and Debug build passed. |

## Recording Rule

P2/P3 visual and interaction findings discovered during the Completion Push belong here or in `KNOWN_LIMITATIONS.md`. They do not stop functional work unless evidence raises them to a data-loss, crash or inaccessible-core-flow risk.
