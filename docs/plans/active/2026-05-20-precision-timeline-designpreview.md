# Precision Timeline DesignPreview Exec Plan

## Goal

Implement a DesignPreview-only second-level precision timeline that expands from `PlayerProgressBar` when the scrubber thumb is double-tapped.

## Confirmed Decisions

- Keep the existing progress bar states: normal, hover, drag.
- Add an expanded timeline state above the progress bar.
- Expanded size target: 960pt wide, about 220pt tall.
- Exit by tapping outside the expanded timeline.
- The playhead is fixed at center; the film/ruler content moves underneath it.
- At media boundaries, the timeline start or end aligns with the playhead and the outside side is empty.
- Zoom is continuous, not discrete.
- Maximum zoom should support frame-level movement.
- Minimum zoom should allow long overview spans, including tens of minutes or more.
- Frame step buttons sit on the two sides of the center playhead.
- Use simulated duration, fps, and thumbnail strips in DesignPreview.

## Non-Blocking Unknowns

- Final production component name may change when replacing the current real app `NLETimelineView`.
- Real thumbnail/keyframe loading is out of scope for this first DesignPreview prototype.
- Production seek throttling policy is out of scope; DesignPreview updates simulated time directly.
- Xcode Preview may not reliably simulate visionOS gaze hover through automation.

## Current Implementation Choices

- Implement inside DesignPreview first, without changing `PlayerUI/NLETimelineView`.
- Use `DesignTokens` for all new sizes, colors, and animation values.
- Use a continuous `pixelsPerSecond` zoom model.
- Use a thumb-local double tap gesture on the thumb hit area for expansion.
- Implemented the expansion trigger with a thumb-local double tap gesture on the existing 60pt thumb hit region.
- Implemented simulated time binding by mapping `PlayerProgressBar.progress` to the DesignPreview fixture duration.
- Implemented frame snapping only when zoom is high enough that one frame has visible point distance.
- Corrected the expanded layout so the timeline occupies real component height instead of relying on a negative offset outside the 60pt progress bar bounds.
- Kept the collapsed progress bar at 680pt wide, then expands the component to 960pt wide and 296pt tall while keeping the progress bar attached to the bottom edge.
- Updated the expansion model to be replacement-style: the original progress bar disappears in expanded mode and the expanded timeline occupies the component directly.
- Added a visible continuous zoom rail in addition to pinch and `- / +`, using logarithmic `pixelsPerSecond` mapping so the time threshold changes smoothly.
- Reworked the simulated thumbnail layer into a film strip with sprocket holes, framed thumbnail cells, separators, and overview-density reduction.
- Restored the rounded viewport mask around the ruler/film area while keeping the internal film content rectangular.
- Removed the textual visible-range label; the zoom rail now carries that state visually.
- Moved the previous/next frame buttons to the two sides of the current timecode.
- Tightened component-local spacing by using smaller existing spacing tokens, without redefining global spacing tokens.
- Let the film strip consume the remaining timeline viewport height so it reads as the primary lower visual.

## Verification Log

- Passed: `git diff --check`.
- Passed: `xcodebuild -project XrPlayer.xcodeproj -scheme DesignPreview -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-DesignPreview-PrecisionTimeline build`.
- Not restarted: existing Xcode Preview simulator was left untouched; verification used a generic build destination only.
- Automation limitation: Computer Use synthetic pointer events are not reliable proof for visionOS Preview hover/double-tap behavior.
- Pending human visual validation: double-tap thumb expansion, outside tap dismissal, continuous zoom, frame buttons, boundary empty space, and frame-level dragging.
- Passed after layout correction: `git diff --check`.
- Passed after layout correction: `xcodebuild -project XrPlayer.xcodeproj -scheme DesignPreview -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-DesignPreview-PrecisionTimeline build`.
- Passed after morph/film/zoom correction: `git diff --check`.
- Passed after morph/film/zoom correction: `xcodebuild -project XrPlayer.xcodeproj -scheme DesignPreview -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-DesignPreview-PrecisionTimeline build`.
- Passed after film mask corner correction: `git diff --check`.
- Passed after film mask corner correction: `xcodebuild -project XrPlayer.xcodeproj -scheme DesignPreview -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-DesignPreview-PrecisionTimeline build`.
- Passed after restoring rounded film viewport with rectangular film content: `git diff --check`.
- Passed after restoring rounded film viewport with rectangular film content: `xcodebuild -project XrPlayer.xcodeproj -scheme DesignPreview -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-DesignPreview-PrecisionTimeline build`.
- Passed after header/spacing/film-height adjustment: `git diff --check`.
- Passed after header/spacing/film-height adjustment: `xcodebuild -project XrPlayer.xcodeproj -scheme DesignPreview -configuration Debug -destination 'generic/platform=visionOS Simulator' -derivedDataPath /tmp/Enchron-DesignPreview-PrecisionTimeline build`.
