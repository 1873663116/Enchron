# RealityKit runtime video-format override research

Date: 2026-08-07

## Question

Can Enchron keep the same RealityKit entity, video-player component, and sample-buffer renderer while changing the sample description and projection tags for a user-selected format override, then ask RealityKit to enter progressive immersive viewing? If that is not supported, which object must be rebuilt first?

## Finding

Apple exposes all of the pieces needed to *express* the least-destructive path, but does not document the end-to-end transition as a supported contract. Core Media can construct tagged sample buffers that identify projection, packing, and stereo views. Apple's stereoscopic-video sample submits such programmatically tagged buffers to an `AVSampleBufferVideoRenderer`, and RealityKit accepts that renderer when a video-player component is created. This establishes that tagged samples are legitimate renderer input.

It does not establish that changing an already-running stream from flat/mono classification to equirectangular or half-equirectangular classification will cause the same RealityKit component to reclassify itself. Apple documents an event that reports content-type changes, but does not state which in-stream format changes must produce that event, whether a decoder flush is required, or whether projection classification can change after the component has bound the renderer.

The least-destructive path is therefore a valid experiment, not a documented guarantee.

## Ownership boundary

The renderer associated with a RealityKit video-player component is read-only after component creation. Apple also states that one renderer cannot be used with more than one such component. Consequently, “same component, replacement renderer” is not a legal rung in the recovery ladder. Replacing the renderer necessarily means replacing the component.

The entity itself is only the component host. No Apple contract found requires replacing the entity when replacing the video-player component. The evidence-consistent ownership ladder is therefore:

1. Keep the entity, component, and renderer; introduce a clean sample-format boundary and test whether RealityKit reclassifies the content.
2. If that is not accepted, keep the entity but replace the video-player component. A replacement renderer may be required at the same boundary.
3. Replace the entity only if an independently reproduced RealityKit lifecycle constraint makes that necessary; it is not implied by the public API.

Whether the same renderer may be detached from one component and then attached to a new component sequentially is not stated precisely enough by Apple to treat as guaranteed. The one-component rule clearly prohibits simultaneous attachment. Sequential rebinding needs its own device proof or should be avoided by constructing a new renderer with the new component.

## Stream-boundary requirements

Apple documents that flushing a sample-buffer video renderer discards pending samples and resets decoder state, and that the next submitted frame should be a key frame. The current Xcode 27 visionOS SDK contains the same contract. Core Media also exposes a per-buffer decoder-reset attachment. These are legal decoder discontinuity mechanisms, but Apple does not say that either mechanism alone causes RealityKit to reconsider immersive content classification.

The narrowest defensible experiment is therefore:

1. stop advancing the existing presentation timeline;
2. flush the renderer at the override boundary while preserving the currently displayed image if desired;
3. resume from a preceding key frame;
4. ensure every sample from the new stream revision carries one internally consistent set of projection, packing, and stereo tags;
5. wait for RealityKit to report the new content type;
6. only then request progressive viewing and wait for RealityKit to confirm the actual viewing mode before completing the scene transition.

Steps 1–4 are an inference from Apple’s decoder and tagged-buffer contracts. Steps 5–6 are the RealityKit confirmation contract. Apple has not published a statement guaranteeing that the complete sequence succeeds without rebuilding the component.

## Apple sample boundary

Apple's immersive-media sample does not demonstrate transferring one entity and one component between the window scene and the immersive scene. It shares the `AVPlayer`, while each scene owns its own RealityKit view, entity, and video-player component. The outgoing view removes its component when it disappears. This is evidence for rebuilding presentation objects around a shared player; it is not evidence that an entity transfer is invalid, and it does not answer the sample-buffer-renderer rebinding question.

## Enchron evidence gap

Enchron currently creates a tagged presentation sample and submits that tagged sample to the renderer. However, its diagnostic record and format verification are derived from the earlier ungrouped sample rather than the actual tagged sample submitted to the renderer. The application can therefore prove that it constructed an override without proving that the renderer received and RealityKit adopted the projection-bearing representation. This does not by itself establish the runtime failure, but it means the current success evidence cannot distinguish “tags were never adopted” from “scene transfer failed later.”

## Required physical-device proof

The first rung is supported for Enchron only when one physical Vision Pro run establishes all of the following for a single transition:

- the entity identity remains unchanged;
- the component and renderer identities remain unchanged;
- the first post-boundary input is a valid key frame and the renderer does not fail;
- the actual submitted tagged sample carries the selected projection and packing;
- RealityKit reports the corresponding immersive content type;
- RealityKit confirms progressive viewing, rather than only recording that it was requested;
- the wearer sees the panorama in the immersive space.

If the renderer accepts the samples but RealityKit never reports the new content type, the least-destructive path has failed at the component's content-classification boundary. The next experiment should keep the entity and rebuild the component, preferably with a fresh renderer. If RealityKit reports the correct content type but never confirms progressive viewing, rebuilding the media objects does not address the demonstrated failure; the fault lies in the viewing-mode or scene contract instead.

## Primary sources

- [VideoPlayerComponent](https://developer.apple.com/documentation/realitykit/videoplayercomponent)
- [VideoPlayerComponent video renderer](https://developer.apple.com/documentation/realitykit/videoplayercomponent/videorenderer)
- [VideoPlayerComponent renderer initializer](https://developer.apple.com/documentation/realitykit/videoplayercomponent/init(videorenderer:))
- [Video content-type change event](https://developer.apple.com/documentation/realitykit/videoplayerevents/contenttypedidchange)
- [Rendering stereoscopic video with RealityKit](https://developer.apple.com/documentation/realitykit/rendering-stereoscopic-video-with-realitykit)
- [Playing immersive media with RealityKit](https://developer.apple.com/documentation/visionos/playing-immersive-media-with-realitykit)
- [Create a great spatial playback experience](https://developer.apple.com/videos/play/wwdc2025/296)
- [Learn about the Apple Projected Media Profile](https://developer.apple.com/videos/play/wwdc2025/297)
- [AVSampleBufferVideoRenderer](https://developer.apple.com/documentation/avfoundation/avsamplebuffervideorenderer)
- [Flush queued sample-buffer rendering](https://developer.apple.com/documentation/avfoundation/avqueuedsamplebufferrendering/flush())

Apple documentation was fetched through Sosumi. Xcode MCP in this environment did not expose a documentation RAG operation, so the second evidence source was the installed Xcode 27 visionOS SDK declarations and headers.

The relevant RealityKit sample-buffer integration begins in visionOS 2.0. Progressive immersive viewing, the projected-content classifications used here, and Apple's tagged-buffer stereoscopic sample are visionOS 26-era contracts. Xcode 27 introduces newer asynchronous renderer-receiver operations and deprecates older queue and flush entry points, but it does not add a documented promise for runtime projection reclassification.
