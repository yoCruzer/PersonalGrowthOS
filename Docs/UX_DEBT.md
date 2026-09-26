# UX Debt

2026-09-26：UX-01/02 均保持 RESOLVED，不重新实现；当前版本仅做代表性图片显示/预览回归。Owner 交互验证已归并到 [当前候选清单](OWNER_MANUAL_VALIDATION_CHECKLIST.md)，下表 Build 5 标记为历史解决时点。

| ID | Priority | Area | Observation | Status | V1 treatment |
| --- | --- | --- | --- | --- | --- |
| UX-01 | P2 | Entry media | Landscape and portrait images shared a portrait-biased container, leaving conspicuous gray side space for landscape images. | RESOLVED — Build 5 candidate | The shared presentation now preserves each image's aspect ratio, removes the forced gray container, and caps only maximum height. Targeted aspect-ratio/media validation and Debug build passed. |
| UX-02 | P2 | Entry media | Images could not be opened in a larger or full-screen preview. | RESOLVED — Build 5 candidate | Entry-detail images now open a lightweight full-screen, aspect-fit preview with a clear close control and thumbnail fallback; no media-browser or editor scope was added. Targeted media validation and Debug build passed. |

## Recording Rule

P2/P3 visual and interaction findings discovered during the Completion Push belong here or in `KNOWN_LIMITATIONS.md`. They do not stop functional work unless evidence raises them to a data-loss, crash or inaccessible-core-flow risk.
