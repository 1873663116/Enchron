(() => {
  "use strict";

  const modelNode = document.getElementById("atlas-model");
  const model = JSON.parse(modelNode.textContent);
  const stateRegistry = model.stateRegistry || {};
  const actions = model.actionRegistry || [];
  const surfaces = model.projection?.surfaces || [];
  const scenes = model.projection?.scenes || [];
  const owners = new Map((model.owners || []).map((item) => [item.id, item]));
  const actors = new Map((model.actorRegistry || []).map((item) => [item.id, item]));
  const sources = new Map((model.sources || []).map((item) => [item.id, item]));
  const surfacesById = new Map(surfaces.map((item) => [item.id, item]));
  const dimensions = new Map((stateRegistry.dimensions || []).map((item) => [item.id, item]));
  const entities = new Map((stateRegistry.entities || []).map((item) => [item.id, item]));
  const actionsById = new Map(actions.map((item) => [item.id, item]));

  const viewButtons = [...document.querySelectorAll("[data-view]")];
  const viewPanels = [...document.querySelectorAll("[data-view-panel]")];
  const stage = document.getElementById("journey-stage");
  const actionGroups = document.getElementById("action-groups");
  const sourceDialog = document.getElementById("source-dialog");
  const sourceDialogContent = document.getElementById("source-dialog-content");
  let currentActionId = actions.find((action) => action.featured)?.id || actions[0]?.id;

  function text(value, fallback = "") {
    return value == null ? fallback : String(value);
  }

  function escapeHTML(value) {
    return text(value)
      .replaceAll("&", "&amp;")
      .replaceAll("<", "&lt;")
      .replaceAll(">", "&gt;")
      .replaceAll('"', "&quot;")
      .replaceAll("'", "&#039;");
  }

  function slugTail(id) {
    return text(id).split(".").pop();
  }

  function statusValue(action, key) {
    if (key === "decision") {
      return action.decisionStatus;
    }
    return action.delivery[key];
  }

  const deliveryLabels = {
    observed: "已在生产代码中观察到",
    notFound: "尚未发现实现",
    notAssessed: "尚未评估实现",
    partial: "仅部分实现",
    verifiedCurrent: "已有当前验证证据",
    historicalEvidence: "仅有历史验证证据",
    blocked: "验证受阻",
    notEvidenced: "尚无验证证据"
  };

  function deliveryLabel(value) {
    if (!(value in deliveryLabels)) throw new Error(`Unsupported delivery status: ${value}`);
    return deliveryLabels[value];
  }

  function isUnresolved(action) {
    return statusValue(action, "decision") !== "confirmed";
  }

  function actionOwnerIds(action) {
    return action.ownerIds || [];
  }

  function actionSourceRefs(action) {
    return Array.isArray(action.sourceRefs) ? action.sourceRefs : [];
  }

  function surfaceActionIds(surface) {
    if (surface.kind === "behavior" || surface.kind === "semantic-rule") return [];
    const ids = new Set();
    for (const action of actions) {
      if ((action.placements || []).some((placement) => placement.surfaceId === surface.id)) {
        ids.add(action.id);
      }
    }
    return [...ids].filter((id) => actionsById.has(id));
  }

  function switchView(id, focus = true) {
    viewButtons.forEach((button) => {
      const active = button.dataset.view === id;
      if (active) button.setAttribute("aria-current", "page");
      else button.removeAttribute("aria-current");
    });
    viewPanels.forEach((panel) => {
      const active = panel.dataset.viewPanel === id;
      panel.hidden = !active;
      panel.classList.toggle("is-active", active);
      if (active && focus) panel.focus({ preventScroll: true });
    });
  }

  function openAction(id) {
    if (!actionsById.has(id)) return;
    currentActionId = id;
    switchView("journeys", false);
    renderActionIndex(document.getElementById("action-search")?.value || "");
    renderAction(actionsById.get(id));
    stage.scrollIntoView({ block: "start", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    stage.focus({ preventScroll: true });
  }

  function surfaceClass(surface) {
    const kind = `${surface.kind || ""} ${surface.id || ""}`.toLowerCase();
    if (kind.includes("immersive")) return "surface-immersive";
    if (kind.includes("control")) return "surface-controls";
    if (kind.includes("volume") || kind.includes("environmentcard")) return "surface-volume";
    return "surface-main-window";
  }

  function sceneClass(scene) {
    const identity = `${scene.kind || ""} ${scene.id || ""}`.toLowerCase();
    if (identity.includes("immersive")) return "surface-immersive";
    if (identity.includes("control")) return "surface-controls";
    if (identity.includes("volume") || identity.includes("environment")) return "surface-volume";
    return "surface-main-window";
  }

  function sceneActionIds(scene) {
    const childIds = new Set(
      (scene.surfaceIds || []).filter((surfaceId) => {
        const kind = surfacesById.get(surfaceId)?.kind;
        return kind !== "behavior" && kind !== "semantic-rule";
      })
    );
    return actions
      .filter((action) => (action.placements || []).some((placement) => childIds.has(placement.surfaceId)))
      .map((action) => action.id);
  }

  function renderWorld() {
    const world = document.getElementById("world-map");
    const selectedScenes = scenes.filter((scene) => scene.kind !== "system").slice(0, 4);
    const selected = selectedScenes.length ? selectedScenes : surfaces.slice(0, 4);

    const surfaceMarkup = selected.map((surface) => {
      const cssClass = selectedScenes.length ? sceneClass(surface) : surfaceClass(surface);
      const ids = selectedScenes.length ? sceneActionIds(surface) : surfaceActionIds(surface);
      const actionButtons = ids
        .slice(0, cssClass === "surface-main-window" ? 7 : 5)
        .map((id) => {
          const action = actionsById.get(id);
          return `<button class="surface-action" type="button" data-action-id="${escapeHTML(id)}" data-unresolved="${isUnresolved(action)}">${escapeHTML(action.label)}</button>`;
        }).join("");
      const special = cssClass === "surface-main-window"
        ? `<div class="video-aperture" aria-hidden="true"></div>`
        : cssClass === "surface-immersive"
          ? `<div class="immersive-anchor" aria-hidden="true"></div>`
          : "";
      return `
        <section class="surface ${cssClass}" aria-label="${escapeHTML(surface.label)}">
          <div class="surface-label"><i></i>${escapeHTML(surface.sceneLabel || surface.kind || "Product Surface")}</div>
          <h3>${escapeHTML(surface.label)}</h3>
          <p class="surface-subtitle">${escapeHTML(surface.summary || surface.description || "")}</p>
          ${special}
          <div class="surface-regions">${actionButtons}</div>
        </section>`;
    }).join("");

    world.innerHTML = `
      <div class="world-map-inner">
        <div class="world-system-label">visionOS · System Surroundings</div>
        ${surfaceMarkup}
        <svg class="world-path" viewBox="0 0 400 180" aria-hidden="true">
          <path d="M10 10 C 80 35, 100 110, 205 110 S 320 120, 390 164"></path>
        </svg>
      </div>`;
    world.querySelectorAll("[data-action-id]").forEach((button) => {
      button.addEventListener("click", () => openAction(button.dataset.actionId));
    });
  }

  function actionCategory(action) {
    return text(action.id).split(".")[0] || "other";
  }

  const categoryLabels = {
    nav: "导航与表面",
    library: "Media Library",
    source: "媒体来源",
    playback: "打开与启动",
    queue: "Playback Queue",
    window: "Window Presentation",
    docked: "Docked",
    panorama: "Panorama",
    presentation: "Presentation 合同",
    controls: "Playback Deck",
    transport: "播放控制",
    more: "More",
    environment: "Environment",
    system: "visionOS 生命周期",
    settings: "Settings"
  };

  function renderActionIndex(query = "") {
    const normalized = query.trim().toLocaleLowerCase("zh-CN");
    const compact = matchMedia("(max-width: 680px)").matches;
    const filtered = actions.filter((action) => {
      if (!normalized) return true;
      const ownerText = actionOwnerIds(action).map((id) => owners.get(id)?.label || id).join(" ");
      const haystack = `${action.label} ${action.summary || ""} ${action.id} ${ownerText}`.toLocaleLowerCase("zh-CN");
      return haystack.includes(normalized);
    });
    const groups = new Map();
    for (const action of filtered) {
      const category = actionCategory(action);
      if (!groups.has(category)) groups.set(category, []);
      groups.get(category).push(action);
    }
    actionGroups.innerHTML = [...groups.entries()].map(([category, groupActions]) => {
      const containsCurrent = groupActions.some((action) => action.id === currentActionId);
      const open = !compact || Boolean(normalized) || containsCurrent;
      return `
      <details class="action-group" ${open ? "open" : ""}>
        <summary>${escapeHTML(categoryLabels[category] || category)} <span>${groupActions.length}</span></summary>
        ${groupActions.map((action) => `
          <button type="button" data-index-action="${escapeHTML(action.id)}" aria-current="${action.id === currentActionId}">
            <span>${escapeHTML(action.label)}</span>
            <i class="mini-status ${isUnresolved(action) ? "unresolved" : ""}" title="${isUnresolved(action) ? "尚未决策" : "已确认"}"></i>
          </button>`).join("")}
      </details>`;
    }).join("") || `<p class="journey-summary">没有匹配的产品操作。</p>`;
    actionGroups.querySelectorAll("[data-index-action]").forEach((button) => {
      button.addEventListener("click", () => openAction(button.dataset.indexAction));
    });
  }

  function demonstrationFor(action) {
    return action.demonstrations?.[0] || { initialState: {}, steps: [], branches: [] };
  }

  function displayPatch(patch) {
    if (!patch || typeof patch !== "object") return [];
    return Object.entries(patch).map(([dimensionId, value]) => {
      const dimension = dimensions.get(dimensionId);
      const valueId = typeof value === "object" ? (value.value || JSON.stringify(value)) : value;
      const valueLabel = dimension?.values?.find((item) => (typeof item === "string" ? item : item.id) === valueId);
      const normalizedLabel = typeof valueLabel === "object" ? valueLabel.label : valueLabel;
      return `${dimension?.label || slugTail(dimensionId)} → ${normalizedLabel || valueId}`;
    });
  }

  function renderGeneric(action) {
    const demo = demonstrationFor(action);
    const initial = demo.initialState && Object.keys(demo.initialState).length
      ? [{ isInitial: true, label: "操作前", patch: demo.initialState }]
      : [];
    const steps = [...initial, ...(demo.steps || [])];
    return `
      <div class="logic-figure">
        <div class="generic-flow" aria-label="${escapeHTML(action.label)} 因果路径">
          ${steps.map((step) => `
            <section class="flow-step">
              <span class="actor">${escapeHTML(step.isInitial ? "操作前状态" : actorLabel(step.actorId))}</span>
              <h3>${escapeHTML(step.label)}</h3>
              ${step.detail || step.description ? `<p>${escapeHTML(step.detail || step.description)}</p>` : ""}
              <div class="state-deltas">${displayPatch(step.patch).map((delta) => `<span class="state-delta">${escapeHTML(delta)}</span>`).join("")}</div>
            </section>`).join("") || `<section class="flow-step"><span class="actor">PRODUCT CONTRACT</span><h3>${escapeHTML(action.summary || action.label)}</h3></section>`}
        </div>
      </div>
      ${renderBranches(action, demo)}`;
  }

  function actorLabel(id) {
    return actors.get(id)?.label || "";
  }

  function renderBranches(action, demo) {
    const branches = demo.branches || [];
    if (!branches.length) return "";
    return `<div class="branch-list" aria-label="异常与系统分支">
      ${branches.map((branch, index) => `<button class="branch-button" type="button" data-branch-index="${index}">${escapeHTML(branch.label || branch.id || `分支 ${index + 1}`)}</button>`).join("")}
    </div>`;
  }

  function spatialVisual(action) {
    const demo = demonstrationFor(action);
    const visual = action.visual || {};
    const phases = visual.phases || demo.steps || [];
    const from = visual.fromSurface || visual.fromLabel || "Window Surface";
    const to = visual.toSurface || visual.toLabel || "Playback Surface Anchor";
    const anchor = visual.anchorLabel || "";
    const invariant = visual.invariantLabel || action.invariantLabel || "同一 Media Session · 同一 Renderer";
    const phaseCount = Math.max(phases.length, 1);
    return `
      <div class="logic-figure spatial-transfer" data-spatial-transfer>
        <svg class="desktop-logic" viewBox="0 0 960 390" role="img" aria-labelledby="spatial-title spatial-desc">
          <title id="spatial-title">${escapeHTML(action.label)}</title>
          <desc id="spatial-desc">同一媒体会话和 renderer 从 Window surface 迁移到 Enchron Immersive Space 内的目标 anchor；失败则回滚原位置。</desc>
          <defs>
            <linearGradient id="window-glass" x1="0" x2="1">
              <stop stop-color="#203143" stop-opacity=".9"/>
              <stop offset="1" stop-color="#111a24" stop-opacity=".64"/>
            </linearGradient>
            <filter id="beam-glow"><feGaussianBlur stdDeviation="5"/></filter>
          </defs>
          <text x="95" y="78" class="tiny">SOURCE PRESENTATION</text>
          <rect x="85" y="95" width="250" height="180" rx="22" fill="url(#window-glass)" stroke="rgba(197,220,244,.28)"/>
          <rect x="126" y="145" width="168" height="93" rx="7" fill="#0d1924" stroke="#75e1e7" stroke-opacity=".6"/>
          <text x="210" y="300" text-anchor="middle" class="label">${escapeHTML(from)}</text>

          <text x="670" y="78" class="tiny">TARGET PRESENTATION</text>
          <ellipse cx="757" cy="230" rx="150" ry="62" fill="rgba(117,225,231,.05)" stroke="rgba(117,225,231,.32)"/>
          <rect x="684" y="139" width="146" height="80" rx="5" fill="rgba(20,47,59,.58)" stroke="#75e1e7" stroke-opacity=".46" class="target-surface"/>
          <circle cx="757" cy="278" r="15" fill="none" stroke="#ffc971" stroke-width="2"/>
          <text x="757" y="325" text-anchor="middle" class="label">${escapeHTML(to)}</text>
          <text x="757" y="343" text-anchor="middle" class="tiny">${escapeHTML(anchor)}</text>

          <path class="session-line beam-blur" d="M294 191 C 455 95, 565 95, 684 179" fill="none" stroke-width="9" opacity=".13" filter="url(#beam-glow)"/>
          <path class="session-line beam-main" d="M294 191 C 455 95, 565 95, 684 179" fill="none" stroke-width="2.5"/>
          <circle class="renderer-token" cx="294" cy="191" r="8" fill="#75e1e7"/>
          <text x="485" y="99" text-anchor="middle" class="small">${escapeHTML(invariant)}</text>
          <path class="transition-line" d="M352 340 H 608" fill="none" stroke-width="1" stroke-dasharray="3 5"/>
          <text x="480" y="365" text-anchor="middle" class="tiny">ATTACH · SETTLE · COMMIT / ROLLBACK</text>
        </svg>
        <div class="mobile-spatial" aria-label="${escapeHTML(action.label)} 从来源到目标的关键路径">
          <div class="mobile-surface source">
            <span>SOURCE</span>
            <i aria-hidden="true"></i>
            <strong>${escapeHTML(from)}</strong>
          </div>
          <div class="mobile-transfer">
            <span class="mobile-session-token" aria-hidden="true"></span>
            <b>${escapeHTML(invariant)}</b>
            <small>ATTACH · SETTLE · COMMIT</small>
          </div>
          <div class="mobile-surface target">
            <span>TARGET</span>
            <i aria-hidden="true"></i>
            <strong>${escapeHTML(to)}</strong>
            ${anchor ? `<small>${escapeHTML(anchor)}</small>` : ""}
          </div>
        </div>
      </div>
      <label class="phase-control">
        <strong data-phase-label>${escapeHTML(phases[0]?.label || "迁移")}</strong>
        <input type="range" min="0" max="${phaseCount - 1}" value="0" step="1" aria-label="${escapeHTML(action.label)} 阶段">
        <span><span data-phase-index>1</span> / ${phaseCount}</span>
      </label>
      ${renderBranches(action, demo)}`;
  }

  function bindSpatial(action) {
    const root = stage.querySelector("[data-spatial-transfer]");
    if (!root) return;
    const range = stage.querySelector(".phase-control input");
    const label = stage.querySelector("[data-phase-label]");
    const index = stage.querySelector("[data-phase-index]");
    const phases = action.visual?.phases || demonstrationFor(action).steps || [];
    const token = root.querySelector(".renderer-token");
    const target = root.querySelector(".target-surface");
    const beam = root.querySelector(".beam-main");
    const length = beam.getTotalLength();
    const update = () => {
      const current = Number(range.value);
      const progress = phases.length <= 1 ? 1 : current / (phases.length - 1);
      const point = beam.getPointAtLength(length * progress);
      token.setAttribute("cx", point.x);
      token.setAttribute("cy", point.y);
      target.style.opacity = `${.22 + progress * .78}`;
      label.textContent = phases[current]?.label || `阶段 ${current + 1}`;
      index.textContent = String(current + 1);
    };
    range.addEventListener("input", update);
    update();
  }

  function projectionVisual(action) {
    const visual = action.visual || {};
    const projections = visual.projectionOptions || [
      { id: "180", label: "180°" },
      { id: "360", label: "360°" },
      { id: "fisheye", label: "Fisheye" }
    ];
    const stereos = visual.stereoOptions || [
      { id: "mono", label: "Mono" },
      { id: "sideBySide", label: "Side-by-Side" },
      { id: "topBottom", label: "Top-Bottom" }
    ];
    const normalize = (item) => typeof item === "string" ? { id: item, label: item } : item;
    const projectionItems = projections.map(normalize);
    const stereoItems = stereos.map(normalize);
    return `
      <div class="logic-figure">
        <div class="format-canvas">
          <div class="format-axes" aria-label="Projection 与 Stereo Layout 两个正交选择轴">
            <div class="format-axis projection-axis">
              <span>Projection →</span>
              <div>
                ${projectionItems.map((item, index) => `<button type="button" class="axis-option projection-option ${index === 0 ? "is-selected" : ""}" data-axis-index="${index}" data-value="${escapeHTML(item.id)}">${escapeHTML(item.label)}</button>`).join("")}
              </div>
            </div>
            <div class="format-intersection" aria-hidden="true">
              <i></i>
              <span>完整 Media Format</span>
            </div>
            <div class="format-axis stereo-axis">
              <span>Stereo Layout ↑</span>
              <div>
                ${stereoItems.map((item, index) => `<button type="button" class="axis-option stereo-option ${index === 0 ? "is-selected" : ""}" data-axis-index="${index}" data-value="${escapeHTML(item.id)}">${escapeHTML(item.label)}</button>`).join("")}
              </div>
            </div>
          </div>
          <div class="projection-scene">
            <div class="projection-surface" data-shape="hemisphere" aria-hidden="true"></div>
            <div class="projection-user" aria-hidden="true"></div>
          </div>
        </div>
      </div>
      <p class="causal-sentence">两个轴分别选择，完整组合在 <strong>Apply</strong> 后一次提交。Presentation 改变，Media Format 仍是独立状态。</p>
      ${renderBranches(action, demonstrationFor(action))}`;
  }

  function bindProjection() {
    const projectionButtons = [...stage.querySelectorAll(".projection-option")];
    const stereoButtons = [...stage.querySelectorAll(".stereo-option")];
    const surface = stage.querySelector(".projection-surface");
    const select = (buttons, chosen) => {
      buttons.forEach((button) => button.classList.toggle("is-selected", button === chosen));
    };
    projectionButtons.forEach((button) => {
      button.addEventListener("click", () => {
        select(projectionButtons, button);
        stage.querySelector(".format-axes")?.style.setProperty("--projection-index", button.dataset.axisIndex || "0");
        const value = button.dataset.value.toLowerCase();
        surface.dataset.shape = value.includes("360") ? "sphere" : value.includes("fish") ? "fisheye" : "hemisphere";
      });
    });
    stereoButtons.forEach((button) => button.addEventListener("click", () => {
      select(stereoButtons, button);
      stage.querySelector(".format-axes")?.style.setProperty("--stereo-index", button.dataset.axisIndex || "0");
    }));
  }

  function lifecycleVisual(action) {
    const visual = action.visual || {};
    const lanes = visual.lanes || [
      { id: "process", label: "App Process", color: "system-line" },
      { id: "space", label: "Immersive Space", color: "transition-line" },
      { id: "intent", label: "Spatial Recovery Intent", color: "intent-line" }
    ];
    return `
      <div class="branch-switch" aria-label="恢复路径">
        <button type="button" aria-pressed="true" data-life-branch="warm">同进程恢复</button>
        <button type="button" aria-pressed="false" data-life-branch="cold">进程被终止</button>
      </div>
      <div class="logic-figure lifecycle-figure">
        <svg class="desktop-logic" viewBox="0 0 980 390" role="img" aria-labelledby="life-title life-desc">
          <title id="life-title">${escapeHTML(action.label)}</title>
          <desc id="life-desc">Home View 关闭 Immersive Space；App 进程仍存在时由内存意图重建，进程终止时恢复意图同时消失并进入冷启动。</desc>
          <line x1="320" y1="45" x2="320" y2="350" stroke="rgba(184,163,255,.34)" stroke-dasharray="4 6"/>
          <text x="320" y="28" text-anchor="middle" class="tiny">HOME VIEW</text>
          <line x1="735" y1="45" x2="735" y2="350" stroke="rgba(126,185,255,.2)" stroke-dasharray="4 6"/>
          <text x="735" y="28" text-anchor="middle" class="tiny life-return-label">REACTIVATE ENCHRON</text>
          ${lanes.map((lane, index) => {
            const y = 105 + index * 100;
            const colorClass = escapeHTML(lane.color || (index === 0 ? "system-line" : index === 1 ? "transition-line" : "intent-line"));
            const line = lane.id === "space"
              ? `<line class="${colorClass} lane-space-old" x1="205" y1="${y}" x2="320" y2="${y}" stroke-width="3"/>
                 <line class="${colorClass} lane-space-new" x1="735" y1="${y}" x2="905" y2="${y}" stroke-width="3"/>`
              : lane.id === "intent"
                ? `<line class="${colorClass} lane-intent" x1="320" y1="${y}" x2="735" y2="${y}" stroke-width="2" fill="none"/>`
                : `<line class="${colorClass} lane-process" x1="205" y1="${y}" x2="905" y2="${y}" stroke-width="3" fill="none"/>`;
            return `
              <text x="32" y="${y + 4}" class="label">${escapeHTML(lane.label)}</text>
              ${line}
              <circle cx="320" cy="${y}" r="5" fill="${index === 2 ? "#ffc971" : index === 1 ? "#7eb9ff" : "#b8a3ff"}"/>
            `;
          }).join("")}
          <text x="468" y="196" class="small space-ended">旧 Space 已结束</text>
          <text x="746" y="196" class="small space-rebuilt">创建新 Space</text>
          <text x="425" y="306" class="small intent-memory">仅存在于当前进程内存</text>
          <g class="cold-only" opacity="0">
            <line x1="545" y1="64" x2="545" y2="342" stroke="#ff9c8c" stroke-width="2"/>
            <text x="545" y="48" text-anchor="middle" fill="#ff9c8c" font-size="10">PROCESS TERMINATED</text>
            <text x="620" y="112" class="small">新进程 · 冷启动</text>
            <text x="620" y="312" class="small">恢复意图不存在</text>
          </g>
        </svg>
        <div class="mobile-lifecycle" aria-label="Home View 后的资源生命周期">
          <div class="mobile-life-event">
            <span>START</span>
            <strong>Docked / Panorama</strong>
          </div>
          <div class="mobile-life-event system-event">
            <span>visionOS</span>
            <strong>Home View 关闭 Immersive Space</strong>
          </div>
          <div class="mobile-life-lanes">
            <div class="life-lane process"><span>App Process</span><i></i><b>同进程仍存在</b></div>
            <div class="life-lane space"><span>Immersive Space</span><i></i><b>旧 Space 已结束</b></div>
            <div class="life-lane intent"><span>Recovery Intent</span><i></i><b>仅在内存保留</b></div>
          </div>
          <div class="mobile-life-result warm-result">
            <span>REACTIVATE</span>
            <strong>重建 Space → 恢复原 Presentation</strong>
          </div>
          <div class="mobile-life-result cold-result">
            <span>NEXT LAUNCH</span>
            <strong>冷启动 · 不恢复空间形态</strong>
          </div>
        </div>
      </div>
      ${renderBranches(action, demonstrationFor(action))}`;
  }

  function bindLifecycle() {
    const buttons = [...stage.querySelectorAll("[data-life-branch]")];
    const figure = stage.querySelector(".lifecycle-figure");
    const svg = figure?.querySelector("svg");
    if (!svg) return;
    const process = svg.querySelector(".lane-process");
    const intent = svg.querySelector(".lane-intent");
    const newSpace = svg.querySelector(".lane-space-new");
    const cold = svg.querySelector(".cold-only");
    const returnLabel = svg.querySelector(".life-return-label");
    const rebuilt = svg.querySelector(".space-rebuilt");
    buttons.forEach((button) => {
      button.addEventListener("click", () => {
        const isCold = button.dataset.lifeBranch === "cold";
        buttons.forEach((item) => item.setAttribute("aria-pressed", String(item === button)));
        cold.setAttribute("opacity", isCold ? "1" : "0");
        returnLabel.textContent = isCold ? "NEXT LAUNCH" : "REACTIVATE ENCHRON";
        rebuilt.textContent = isCold ? "不恢复空间形态" : "创建新 Space";
        figure.classList.toggle("is-cold", isCold);
        process?.setAttribute("x2", isCold ? "545" : "905");
        intent?.setAttribute("x2", isCold ? "545" : "735");
        newSpace?.setAttribute("opacity", isCold ? "0" : "1");
      });
    });
  }

  function renderResponsibility(action) {
    const steps = actionOwnerIds(action).map((ownerId) => ({
      ownerId,
      label: owners.get(ownerId)?.responsibility || owners.get(ownerId)?.label || ownerId
    }));
    return steps.map((step) => `
      <div class="responsibility-step">
        <span class="actor">${escapeHTML(owners.get(step.ownerId)?.label || step.ownerId)}</span>
        <span>${escapeHTML(step.label || step.description || "")}</span>
      </div>`).join("") || `<p class="journey-summary">责任路径尚未登记。</p>`;
  }

  function renderSourceButtons(sourceRefs) {
    return sourceRefs.map((ref, index) => {
      const source = sources.get(ref.sourceId);
      const label = `${source?.label || ref.sourceId}${ref.heading ? ` · ${ref.heading.replace(/^#+\s*/, "")}` : ""}`;
      return `<button class="source-link" type="button" data-source-index="${index}">${escapeHTML(label)}</button>`;
    }).join("") || `<p>尚无一手来源。</p>`;
  }

  function renderAction(action) {
    const grammar = action.visualGrammar;
    let figure;
    if (grammar === "spatial-transition") figure = spatialVisual(action);
    else if (grammar === "format-to-space-transition") figure = projectionVisual(action);
    else if (grammar === "system-interruption") figure = lifecycleVisual(action);
    else if (["causal-chain", "state-difference", "queue-sequence"].includes(grammar)) figure = renderGeneric(action);
    else throw new Error(`Unsupported visualGrammar: ${grammar}`);
    const sourceRefs = actionSourceRefs(action);
    const invariantIds = action.invariantIds || [];
    const invariantLabels = invariantIds.map((item) => {
      if (typeof item === "object") return item.label || item.id;
      return stateRegistry.invariants?.find((entry) => entry.id === item)?.label || item;
    });
    const implementation = statusValue(action, "implementation");
    const verification = statusValue(action, "verification");
    stage.innerHTML = `
      <a class="registry-jump" href="#action-search">浏览全部 ${actions.length} 项产品操作</a>
      <header class="journey-head">
        <div>
          <p class="section-kicker">${escapeHTML(text(grammar, "product action").replaceAll("-", " "))}</p>
          <h2>${escapeHTML(action.label)}</h2>
          <p class="journey-summary">${escapeHTML(action.summary || action.description || "")}</p>
        </div>
        <span class="decision-badge ${isUnresolved(action) ? "unresolved" : ""}">${isUnresolved(action) ? "尚未决策" : "产品事实已确认"}</span>
      </header>
      ${figure}
      <div class="journey-explanation">
        <div>
          <p class="causal-sentence">${escapeHTML(action.explanation || action.causalSummary || action.summary || "")}</p>
          <div class="invariant-strip">${invariantLabels.map((label) => `<span class="invariant-chip">${escapeHTML(label)}</span>`).join("")}</div>
        </div>
        <div class="responsibility-chain">${renderResponsibility(action)}</div>
      </div>
      <div class="journey-meta">
        <section class="meta-section">
          <h3>所有者与编译边界</h3>
          <p>${actionOwnerIds(action).map((id) => {
            const owner = owners.get(id);
            return `<strong>${escapeHTML(owner?.label || id)}</strong>${owner?.compilerBoundary || owner?.boundary ? `<span>${escapeHTML(owner.compilerBoundary || owner.boundary)}</span>` : ""}`;
          }).join("<br>") || "尚未登记"}</p>
        </section>
        <section class="meta-section delivery-only">
          <h3>交付状态</h3>
          <p>实现：${escapeHTML(deliveryLabel(implementation))}<br>验证：${escapeHTML(deliveryLabel(verification))}</p>
        </section>
        <section class="meta-section">
          <h3>一手来源</h3>
          <div class="source-buttons">${renderSourceButtons(sourceRefs)}</div>
        </section>
      </div>`;
    bindSourceButtons(stage, sourceRefs);
    bindBranchButtons(action);
    if (grammar === "spatial-transition") bindSpatial(action);
    if (grammar === "format-to-space-transition") bindProjection();
    if (grammar === "system-interruption") bindLifecycle();
  }

  function bindBranchButtons(action) {
    const demo = demonstrationFor(action);
    const branches = demo.branches || [];
    stage.querySelectorAll("[data-branch-index]").forEach((button) => {
      button.addEventListener("click", () => {
        const branch = branches[Number(button.dataset.branchIndex)];
        if (!branch) return;
        const existing = stage.querySelector(".branch-explanation");
        existing?.remove();
        const block = document.createElement("div");
        block.className = "branch-explanation generic-flow";
        const steps = branch.steps || [];
        block.innerHTML = steps.length
          ? steps.map((step) => `<section class="flow-step"><span class="actor">${escapeHTML(actorLabel(step.actorId))}</span><h3>${escapeHTML(step.label || branch.label)}</h3><p>${escapeHTML(step.detail || step.description || "")}</p></section>`).join("")
          : `<section class="flow-step"><span class="actor">BRANCH</span><h3>${escapeHTML(branch.label || branch.id)}</h3><p>${escapeHTML(branch.result || branch.description || "")}</p></section>`;
        button.closest(".branch-list").insertAdjacentElement("afterend", block);
      });
    });
  }

  function renderStates() {
    const target = document.getElementById("state-map");
    const dimensionMarkup = (stateRegistry.dimensions || []).map((dimension) => {
      const values = (dimension.values || []).map((value) => typeof value === "string" ? { id: value, label: value } : value);
      return `
        <section class="state-axis">
          <div>
            <h3>${escapeHTML(dimension.label)}</h3>
            <p>${escapeHTML(dimension.summary || dimension.description || "")}</p>
          </div>
          <div class="axis-track" aria-label="${escapeHTML(dimension.label)} 可用值">
            ${values.map((value) => `<span class="axis-value">${escapeHTML(value.label || value.id)}</span>`).join("")}
          </div>
        </section>`;
    }).join("");
    const invariantMarkup = (stateRegistry.invariants || []).map((item) => `<li>${escapeHTML(item.label || item.description || item.id)}</li>`).join("");
    const constraintMarkup = (stateRegistry.constraints || []).map((item) => `<li>${escapeHTML(item.label || item.description || item.id)}</li>`).join("");
    target.innerHTML = `
      ${dimensionMarkup}
      <section class="boundary-section">
        <div>
          <h3>必须保持</h3>
          <ul class="boundary-list">${invariantMarkup}</ul>
        </div>
        <div>
          <h3>禁止组合</h3>
          <ul class="boundary-list constraints">${constraintMarkup}</ul>
        </div>
      </section>`;
  }

  function unresolvedItems() {
    const explicit = model.unresolvedNodes || [];
    const actionGaps = actions.filter(isUnresolved).map((action) => ({
      id: `gap.${action.id}`,
      actionId: action.id,
      label: action.label,
      description: action.summary || action.description || "该动作尚未形成完整产品合同。",
      sourceRefs: action.sourceRefs || []
    }));
    return [...explicit, ...actionGaps.filter((gap) => !explicit.some((item) => item.id === gap.id || item.actionId === gap.id.slice(4)))];
  }

  const gapClusters = {
    source: {
      label: "来源、引用与访问生命周期",
      impact: "影响路径：Source Browser → Media Reference → 播放访问租约"
    },
    environment: {
      label: "Environment 与空间切换",
      impact: "影响路径：Docked / Enchron Immersive Space → Window → Environment Card"
    },
    settings: {
      label: "Settings 与观看数据",
      impact: "影响路径：Settings → Persistent Viewing State"
    },
    other: {
      label: "其他产品边界",
      impact: "影响路径：对应操作所在的产品表面"
    }
  };

  function gapClusterId(gap) {
    const action = actionsById.get(gap.actionId);
    const prefix = text(action?.id || gap.id).replace(/^gap\./, "").split(".")[0];
    return gapClusters[prefix] ? prefix : "other";
  }

  function renderGaps() {
    const gaps = unresolvedItems();
    document.getElementById("gap-count").textContent = String(gaps.length);
    const target = document.getElementById("gap-list");
    const groups = new Map();
    gaps.forEach((gap, index) => {
      const clusterId = gapClusterId(gap);
      if (!groups.has(clusterId)) groups.set(clusterId, []);
      groups.get(clusterId).push({ gap, index });
    });
    target.innerHTML = [...groups.entries()].map(([clusterId, items]) => {
      const cluster = gapClusters[clusterId] || gapClusters.other;
      return `
        <section class="gap-cluster">
          <header>
            <p>${escapeHTML(cluster.impact)}</p>
            <h3>${escapeHTML(cluster.label)}</h3>
            <span>${items.length} 项</span>
          </header>
          <div>
            ${items.map(({ gap, index }) => `
              <article class="gap-item">
                <h4>${escapeHTML(gap.label || gap.title || gap.id)}</h4>
                <p>${escapeHTML(gap.description || gap.summary || "")}</p>
                <div class="gap-source-buttons" data-gap-index="${index}">${renderSourceButtons(gap.sourceRefs || [])}</div>
              </article>`).join("")}
          </div>
        </section>`;
    }).join("") || `<p class="journey-summary">当前没有登记的未决产品问题。</p>`;
    gaps.forEach((gap, index) => {
      const container = target.querySelector(`[data-gap-index="${index}"]`);
      bindSourceButtons(container, gap.sourceRefs || []);
    });
  }

  function bindSourceButtons(root, refs) {
    root?.querySelectorAll("[data-source-index]").forEach((button) => {
      button.addEventListener("click", () => openSource(refs[Number(button.dataset.sourceIndex)]));
    });
  }

  function openSource(ref) {
    const source = sources.get(ref.sourceId);
    sourceDialogContent.innerHTML = `
      <p class="section-kicker">PRIMARY SOURCE POINTER</p>
      <h2>${escapeHTML(source?.label || ref.sourceId)}</h2>
      <p>此引用只负责定位，不代表 Atlas 可以覆盖一手文档。</p>
      <div class="source-path">${escapeHTML(source?.path || ref.sourceId)}${ref.heading ? `\n${ref.heading}` : ""}</div>`;
    sourceDialog.showModal();
  }

  function init() {
    viewButtons.forEach((button) => button.addEventListener("click", () => switchView(button.dataset.view)));

    document.getElementById("toggle-delivery").addEventListener("click", (event) => {
      const active = event.currentTarget.getAttribute("aria-pressed") !== "true";
      event.currentTarget.setAttribute("aria-pressed", String(active));
      document.body.classList.toggle("show-delivery", active);
    });

    document.getElementById("open-help").addEventListener("click", (event) => {
      const help = document.getElementById("help-panel");
      const open = help.hidden;
      help.hidden = !open;
      event.currentTarget.setAttribute("aria-expanded", String(open));
    });

    document.getElementById("action-search").addEventListener("input", (event) => renderActionIndex(event.target.value));

    document.addEventListener("keydown", (event) => {
      if (!event.target.closest(".atlas-nav")) return;
      const current = viewButtons.indexOf(document.activeElement);
      if (current < 0) return;
      let next = null;
      if (event.key === "ArrowRight") next = (current + 1) % viewButtons.length;
      if (event.key === "ArrowLeft") next = (current - 1 + viewButtons.length) % viewButtons.length;
      if (event.key === "Home") next = 0;
      if (event.key === "End") next = viewButtons.length - 1;
      if (next != null) {
        event.preventDefault();
        viewButtons[next].focus();
        viewButtons[next].click();
      }
    });

    renderWorld();
    renderActionIndex();
    if (currentActionId) renderAction(actionsById.get(currentActionId));
    else stage.innerHTML = `<p class="journey-summary">Product Action Registry 为空。</p>`;
    renderStates();
    renderGaps();
    document.getElementById("source-status").textContent = `${sources.size} 份一手来源 · ${actions.length} 项产品操作`;
  }

  init();
})();
