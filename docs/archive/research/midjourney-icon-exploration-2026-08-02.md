# Midjourney icon exploration workflow

Research date: 2026-08-02

Midjourney prompts work best when they describe visible content with short, precise language. For the Enchron icon, the prompt should define the ring geometry, gap position and size, cut faces, fragments, central negative space, composition, and rendering medium. The product philosophy should appear only as a short semantic calibration; it should not replace observable shape constraints. Parameters belong at the end of the prompt.

When a reference image should contribute only color, light, or finish, use it as a Style Reference rather than as a normal image prompt. Describe can help extract vocabulary, but its suggestions are exploratory rather than exact descriptions.

The recommended exploration funnel is:

1. Use the current Web Draft mode to generate a broad shape set without color references.
2. Select a small number of promising silhouettes and refine them with Vary or Remix.
3. Keep the selected structure stable and introduce the color reference as a Style Reference.
4. Compare controlled variants with a shared seed before producing final high-resolution candidates.

Midjourney does not currently publish an official API, CLI, or MCP. Community tools generally depend on cookies, undocumented web endpoints, Discord self-bots, browser automation, or third-party proxy services. Midjourney's terms prohibit automated tools that access or interact with the service, so these tools should not be connected to a real account without explicit authorization from Midjourney.

The earlier long, specification-like prompts are not the official best practice. Midjourney recommends short, simple prompts and adding detail only when a specific detail matters. Public logo-prompt examples repeatedly use a compact vocabulary such as `minimal vector logo`, `flat icon`, `simple geometry`, `negative space`, `bold silhouette`, `crisp edges`, and `limited palette`. These are visual cues, not guarantees of an SVG result. For this icon, avoid `Ensō`, `ink`, `brush`, `shattered`, `splatter`, `explosion`, `organic`, `glossy`, `glass`, and `neon` during the shape pass because they tend to pull the result toward painting, debris, or 3D effects. Change one variable per iteration: first gap geometry, then fragment layout, then color.

Additional references:

- [Midjourney Prompt Basics](https://docs.midjourney.com/docs/prompts)
- [Midjourney Multi-Prompts and Weights](https://docs.midjourney.com/hc/en-us/articles/32658968492557-Multi-Prompts-Weights)
- [SREF Midjourney logo prompt examples](https://sref-midjourney.com/prompts/logos) (community vocabulary, not official guidance)
- [PromptSpace logo workflow](https://www.promptspace.in/prompts/midjourney/logo-design) (community workflow, not official guidance)
- [r/midjourney logo discussion](https://www.reddit.com/r/midjourney/comments/18pm1v9) (community discussion, not official guidance)

Primary sources:

- [Prompts](https://docs.midjourney.com/docs/prompts)
- [Version](https://docs.midjourney.com/hc/en-us/articles/32199405667853-Version)
- [Draft and Conversational Modes](https://docs.midjourney.com/hc/en-us/articles/35577175650957-Draft-Conversational-Modes)
- [Style Reference](https://docs.midjourney.com/hc/en-us/articles/32180011136653-Style-Reference)
- [Describe](https://docs.midjourney.com/hc/en-us/articles/32497889043981-Describe)
- [Parameter List](https://docs.midjourney.com/hc/en-us/articles/32859204029709-Parameter-List)
- [Permutations](https://docs.midjourney.com/hc/en-us/articles/32761322355597-Permutations)
- [No](https://docs.midjourney.com/hc/en-us/articles/32173351982093-No)
- [Terms of Service](https://docs.midjourney.com/docs/terms-of-service)
