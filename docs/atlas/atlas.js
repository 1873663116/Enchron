(() => {
  "use strict";

  const modelNode = document.getElementById("atlas-model");
  const model = JSON.parse(modelNode.textContent);
  const stateRegistry = model.stateRegistry || {};
  const actions = model.actionRegistry || [];
  const surfaces = model.projection?.surfaces || [];
  const scenes = model.projection?.scenes || [];
  const stateLandscape = model.projection?.stateLandscape;
  const owners = new Map((model.owners || []).map((item) => [item.id, item]));
  const actors = new Map((model.actorRegistry || []).map((item) => [item.id, item]));
  const sources = new Map((model.sources || []).map((item) => [item.id, item]));
  const surfacesById = new Map(surfaces.map((item) => [item.id, item]));
  const dimensions = new Map((stateRegistry.dimensions || []).map((item) => [item.id, item]));
  const entities = new Map((stateRegistry.entities || []).map((item) => [item.id, item]));
  const actionsById = new Map(actions.map((item) => [item.id, item]));
  const initialQuery = new URLSearchParams(window.location.search);
  const initialView = "journeys";

  const viewButtons = [...document.querySelectorAll("[data-view]")];
  const viewPanels = [...document.querySelectorAll("[data-view-panel]")];
  const stage = document.getElementById("journey-stage");
  const actionGroups = document.getElementById("action-groups");
  const sourceDialog = document.getElementById("source-dialog");
  const sourceDialogContent = document.getElementById("source-dialog-content");
  let currentActionId = actionsById.has(initialQuery.get("action"))
    ? initialQuery.get("action")
    : actions.find((action) => action.featured)?.id || actions[0]?.id;
  let currentActionLayer = ["journey", "blueprint", "machine"].includes(initialQuery.get("layer"))
    ? initialQuery.get("layer")
    : "journey";
  let currentDemonstrationIndex = 0;
  let currentLandscapeSnapshotId = stateLandscape.snapshots[0].id;
  let currentLandscapeBranchId = null;
  let currentLandscapeFocus = "visible";

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

  function structureActionIds(node) {
    const query = node.relatedActions;
    if (query.bySceneId) {
      const scene = scenes.find((item) => item.id === query.bySceneId);
      const sceneSurfaceIds = new Set(scene.surfaceIds || []);
      return actions
        .filter((action) => (action.placements || []).some((placement) => sceneSurfaceIds.has(placement.surfaceId)))
        .map((action) => action.id);
    }
    if (query.bySurfaceId) {
      return surfaceActionIds(surfacesById.get(query.bySurfaceId));
    }
    return [...query.actionIds];
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
    currentActionLayer = "journey";
    currentDemonstrationIndex = 0;
    switchView("journeys", false);
    renderActionIndex(document.getElementById("action-search")?.value || "");
    renderAction(actionsById.get(id));
    stage.scrollIntoView({ block: "start", behavior: matchMedia("(prefers-reduced-motion: reduce)").matches ? "auto" : "smooth" });
    stage.focus({ preventScroll: true });
  }

  function renderWorld() {
    const world = document.getElementById("world-map");
    const structureMap = model.projection.structureMap;
    const sceneById = new Map(scenes.map((scene) => [scene.id, scene]));
    const nodeById = new Map(structureMap.nodes.map((node) => [node.id, node]));
    const childNodes = new Map();
    structureMap.nodes.forEach((node) => {
      if (!node.parentNodeId) return;
      if (!childNodes.has(node.parentNodeId)) childNodes.set(node.parentNodeId, []);
      childNodes.get(node.parentNodeId).push(node);
    });

    function nodeSurfaceLabels(node) {
      const scene = node.sceneId ? sceneById.get(node.sceneId) : null;
      const ids = scene?.surfaceIds || (node.surfaceId ? [node.surfaceId] : []);
      return ids
        .map((id) => surfacesById.get(id)?.label)
        .filter(Boolean)
        .slice(0, 3);
    }

    function nodeButton(node, nested = false) {
      const keySurfaces = nodeSurfaceLabels(node);
      return `
        <button class="structure-object structure-${escapeHTML(node.role)}${nested ? " structure-port" : ""}" type="button" data-structure-node="${escapeHTML(node.id)}" aria-pressed="false">
          <span class="structure-kind">${escapeHTML(node.kind)}</span>
          <strong>${escapeHTML(node.label)}</strong>
          <small>${escapeHTML(node.responsibility)}</small>
          <span class="structure-surfaces">${keySurfaces.map((label) => `<i>${escapeHTML(label)}</i>`).join("")}</span>
        </button>`;
    }

    const rootMarkup = structureMap.nodes
      .filter((node) => !node.parentNodeId)
      .map((node) => {
        const children = childNodes.get(node.id) || [];
        if (!children.length) return nodeButton(node);
        return `
          <section class="structure-object structure-${escapeHTML(node.role)} structure-container" data-structure-node="${escapeHTML(node.id)}">
            <button class="structure-container-label" type="button" data-structure-select="${escapeHTML(node.id)}" aria-pressed="false">
              <span class="structure-kind">${escapeHTML(node.kind)}</span>
              <strong>${escapeHTML(node.label)}</strong>
              <small>${escapeHTML(node.responsibility)}</small>
            </button>
            <div class="structure-ports">${children.map((child) => nodeButton(child, true)).join("")}</div>
          </section>`;
      })
      .join("");

    world.innerHTML = `
      <section class="structure-system-context" data-structure-node="${escapeHTML(structureMap.systemContext.id)}">
        <header>
          <span>外部系统上下文</span>
          <strong>${escapeHTML(structureMap.systemContext.label)}</strong>
          <small>${escapeHTML(structureMap.systemContext.responsibility)}</small>
        </header>
        <div class="structure-diagram">
          ${rootMarkup}
          <svg class="structure-links" aria-label="系统结构关系"></svg>
        </div>
      </section>
      <aside class="structure-detail" id="structure-detail" aria-live="polite">
        <span>自由查看</span>
        <strong>选择一个对象</strong>
        <p>图谱将只高亮该对象及其直接关系。</p>
      </aside>`;
    const diagram = world.querySelector(".structure-diagram");
    const links = world.querySelector(".structure-links");
    const detail = world.querySelector("#structure-detail");

    function nodeElement(nodeId) {
      return world.querySelector(`[data-structure-node="${CSS.escape(nodeId)}"]`);
    }

    function anchor(nodeId, side) {
      const box = nodeElement(nodeId).getBoundingClientRect();
      const diagramBox = diagram.getBoundingClientRect();
      const points = {
        top: [box.left + box.width / 2, box.top],
        right: [box.right, box.top + box.height / 2],
        bottom: [box.left + box.width / 2, box.bottom],
        left: [box.left, box.top + box.height / 2]
      };
      return [points[side][0] - diagramBox.left, points[side][1] - diagramBox.top];
    }

    function relationGeometry(relation) {
      const narrow = matchMedia("(max-width: 680px)").matches;
      if (relation.role === "environment") {
        const [x1, y1] = anchor(relation.fromNodeId, "bottom");
        const [x2, y2] = anchor(relation.toNodeId, "top");
        return {
          path: `M ${x1} ${y1} L ${x2} ${y2}`,
          x: narrow ? (x1 + x2) / 2 + 42 : x1 + (x2 - x1) * .22 + 34,
          y: narrow ? y1 + (y2 - y1) * .25 : y1 + (y2 - y1) * .22
        };
      }
      if (relation.role === "controls") {
        const [x1, y1] = anchor(relation.fromNodeId, "top");
        const [x2, y2] = anchor(relation.toNodeId, "bottom");
        return {
          path: `M ${x1} ${y1} L ${x2} ${y2}`,
          x: narrow ? (x1 + x2) / 2 + 36 : x1 + (x2 - x1) * .28 + 38,
          y: narrow ? (y1 + y2) / 2 + 10 : y1 + (y2 - y1) * .28
        };
      }
      if (relation.role === "session") {
        const [x1, y1] = anchor(relation.fromNodeId, "bottom");
        const [x2, y2] = anchor(relation.toNodeId, "bottom");
        const gutter = Math.max(y1, y2) + 44;
        return {
          path: `M ${x1} ${y1} L ${x1} ${gutter} L ${x2} ${gutter} L ${x2} ${y2}`,
          x: Math.min(x1 + 88, (x1 + x2) / 2),
          y: gutter
        };
      }
      if (narrow) {
        const [x1, y1] = anchor(relation.fromNodeId, "bottom");
        const [x2, y2] = anchor(relation.toNodeId, "top");
        const isPresentation = relation.role === "presentation";
        return {
          path: `M ${x1} ${y1} L ${x2} ${y2}`,
          x: (x1 + x2) / 2 + (isPresentation ? -42 : 42),
          y: (y1 + y2) / 2 + (isPresentation ? -12 : 12)
        };
      }
      const [x1, y1] = anchor(relation.fromNodeId, "right");
      const [x2, y2] = anchor(relation.toNodeId, "left");
      return {
        path: `M ${x1} ${y1} L ${x2} ${y2}`,
        x: Math.min(x1 + 76, (x1 + x2) / 2),
        y: y1 - 9
      };
    }

    function drawStructureRelations() {
      const box = diagram.getBoundingClientRect();
      links.setAttribute("viewBox", `0 0 ${box.width} ${box.height}`);
      links.innerHTML = `
        <defs>
          <marker id="structure-arrow" viewBox="0 0 8 8" refX="7" refY="4" markerWidth="7" markerHeight="7" orient="auto">
            <path d="M 0 0 L 8 4 L 0 8 z"></path>
          </marker>
        </defs>
        ${structureMap.relations.map((relation) => {
          const geometry = relationGeometry(relation);
          const detailText = relation.detail ? ` · ${relation.detail}` : "";
          return `
            <g class="structure-relation relation-${escapeHTML(relation.role)}" data-structure-relation="${escapeHTML(relation.id)}" data-from="${escapeHTML(relation.fromNodeId)}" data-to="${escapeHTML(relation.toNodeId)}">
              <title>${escapeHTML(relation.label + detailText)}</title>
              <path d="${escapeHTML(geometry.path)}" marker-end="url(#structure-arrow)"></path>
              <text x="${geometry.x}" y="${geometry.y - 7}" text-anchor="middle">${escapeHTML(relation.label)}</text>
            </g>`;
        }).join("")}`;
    }

    function selectNode(nodeId) {
        const definition = nodeById.get(nodeId);
        const relatedIds = new Set([nodeId]);
        world.querySelectorAll("[data-from][data-to]").forEach((relation) => {
          const related = relation.dataset.from === nodeId || relation.dataset.to === nodeId;
          relation.classList.toggle("is-related", related);
          if (related) {
            relatedIds.add(relation.dataset.from);
            relatedIds.add(relation.dataset.to);
          }
        });
        [...relatedIds].forEach((relatedId) => {
          let ancestorId = nodeById.get(relatedId)?.parentNodeId;
          while (ancestorId) {
            relatedIds.add(ancestorId);
            ancestorId = nodeById.get(ancestorId)?.parentNodeId;
          }
        });
        world.querySelectorAll(".structure-object").forEach((node) => {
          const selected = node.dataset.structureNode === nodeId;
          const control = node.matches("button") ? node : node.querySelector(".structure-container-label");
          control?.setAttribute("aria-pressed", String(selected));
          node.classList.toggle("is-related", relatedIds.has(node.dataset.structureNode));
        });
        world.classList.add("has-structure-selection");
        const actionIds = structureActionIds(definition);
        detail.innerHTML = `
          <span>${escapeHTML(definition.kind)}</span>
          <strong>${escapeHTML(definition.label)}</strong>
          <p>${escapeHTML(definition.responsibility)}</p>
          ${actionIds.length ? `
            <details class="structure-actions">
              <summary>查看 ${actionIds.length} 项相关操作</summary>
              <div>${actionIds.map((actionId) => `<button type="button" data-related-action="${escapeHTML(actionId)}">${escapeHTML(actionsById.get(actionId).label)}</button>`).join("")}</div>
            </details>` : ""}`;
        detail.querySelectorAll("[data-related-action]").forEach((actionButton) => {
          actionButton.addEventListener("click", () => openAction(actionButton.dataset.relatedAction));
        });
    }

    world.querySelectorAll("button[data-structure-node]").forEach((button) => {
      button.addEventListener("click", () => selectNode(button.dataset.structureNode));
    });
    world.querySelectorAll("[data-structure-select]").forEach((button) => {
      button.addEventListener("click", () => selectNode(button.dataset.structureSelect));
    });
    drawStructureRelations();
    new ResizeObserver(drawStructureRelations).observe(diagram);
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

  function demonstrationFor(action, index = currentDemonstrationIndex) {
    return action.demonstrations?.[index] || action.demonstrations?.[0] || { initialState: {}, steps: [], branches: [] };
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
      <div class="logic-figure journey-river" aria-label="${escapeHTML(action.label)} 产品旅程">
        <div class="journey-continuity" aria-hidden="true"></div>
        ${steps.map((step, index) => `
          <section class="journey-moment">
            <span class="journey-number">${String(index + 1).padStart(2, "0")}</span>
            <div class="journey-marker" aria-hidden="true"></div>
            <div class="journey-copy">
              <span class="actor">${escapeHTML(step.isInitial ? "操作前状态" : actorLabel(step.actorId))}</span>
              <h3>${escapeHTML(step.label)}</h3>
              ${step.detail || step.description ? `<p>${escapeHTML(step.detail || step.description)}</p>` : ""}
              <div class="state-deltas">${displayPatch(step.patch).map((delta) => `<span class="state-delta">${escapeHTML(delta)}</span>`).join("")}</div>
            </div>
          </section>`).join("") || `<section class="journey-moment"><span class="journey-number">01</span><div class="journey-marker"></div><div class="journey-copy"><span class="actor">PRODUCT CONTRACT</span><h3>${escapeHTML(action.summary || action.label)}</h3></div></section>`}
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
    const phases = visual.phases;
    const from = visual.fromSurface;
    const to = visual.toSurface;
    const anchor = visual.anchorLabel || "";
    const invariant = visual.invariantLabel;
    const phaseCount = Math.max(phases.length, 1);
    return `
      <div class="logic-figure spatial-transfer" data-spatial-transfer>
        <svg class="desktop-logic" viewBox="0 0 960 390" role="img" aria-labelledby="spatial-title spatial-desc">
          <title id="spatial-title">${escapeHTML(action.label)}</title>
          <desc id="spatial-desc">同一媒体会话和 renderer 从 Window surface 迁移到 Enchron Immersive Space 内的目标 anchor；失败则回滚原位置。</desc>
          <defs>
            <linearGradient id="window-glass" x1="0" x2="1">
              <stop stop-color="var(--glass-strong)" stop-opacity=".9"/>
              <stop offset="1" stop-color="var(--glass)" stop-opacity=".82"/>
            </linearGradient>
            <filter id="beam-glow"><feGaussianBlur stdDeviation="5"/></filter>
          </defs>
          <text x="95" y="78" class="tiny">SOURCE PRESENTATION</text>
          <rect x="85" y="95" width="250" height="180" rx="22" fill="url(#window-glass)" stroke="var(--line)"/>
          <rect x="126" y="145" width="168" height="93" rx="7" fill="var(--glass)" stroke="var(--cyan)" stroke-opacity=".6"/>
          <text x="210" y="300" text-anchor="middle" class="label">${escapeHTML(from)}</text>

          <text x="670" y="78" class="tiny">TARGET PRESENTATION</text>
          <ellipse cx="757" cy="230" rx="150" ry="62" fill="var(--glass)" stroke="var(--cyan)" stroke-opacity=".32"/>
          <rect x="684" y="139" width="146" height="80" rx="5" fill="var(--glass)" stroke="var(--cyan)" stroke-opacity=".46" class="target-surface"/>
          <circle cx="757" cy="278" r="15" fill="none" stroke="var(--amber)" stroke-width="2"/>
          <text x="757" y="325" text-anchor="middle" class="label">${escapeHTML(to)}</text>
          <text x="757" y="343" text-anchor="middle" class="tiny">${escapeHTML(anchor)}</text>

          <path class="session-line beam-blur" d="M294 191 C 455 95, 565 95, 684 179" fill="none" stroke-width="9" opacity=".13" filter="url(#beam-glow)"/>
          <path class="session-line beam-main" d="M294 191 C 455 95, 565 95, 684 179" fill="none" stroke-width="2.5"/>
          <circle class="renderer-token" cx="294" cy="191" r="8" fill="var(--cyan)"/>
          <text x="485" y="99" text-anchor="middle" class="small">${escapeHTML(invariant)}</text>
          <path class="transition-line" d="M352 340 H 608" fill="none" stroke-width="1" stroke-dasharray="3 5"/>
          <text x="480" y="365" text-anchor="middle" class="tiny">${escapeHTML(visual.transactionLabel)}</text>
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
            <small>${escapeHTML(visual.transactionLabel)}</small>
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
    const phases = action.visual.phases;
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
    const projections = visual.projectionOptions;
    const stereos = visual.stereoOptions;
    const normalize = (item) => typeof item === "string" ? { id: item, label: item } : item;
    const projectionItems = projections.map(normalize);
    const stereoItems = stereos.map(normalize);
    const selectedProjection = visual.selected.projection;
    const selectedStereo = visual.selected.stereo;
    return `
      <div class="logic-figure">
        <div class="format-canvas">
          <div class="format-axes" aria-label="Projection 与 Stereo Layout 两个正交选择轴">
            <div class="format-axis projection-axis">
              <span>Projection →</span>
              <div>
                ${projectionItems.map((item, index) => `<button type="button" class="axis-option projection-option ${item.id === selectedProjection ? "is-selected" : ""}" data-axis-index="${index}" data-value="${escapeHTML(item.id)}">${escapeHTML(item.label)}</button>`).join("")}
              </div>
            </div>
            <div class="format-intersection" aria-hidden="true">
              <i></i>
              <span>完整 Media Format</span>
            </div>
            <div class="format-axis stereo-axis">
              <span>Stereo Layout ↑</span>
              <div>
                ${stereoItems.map((item, index) => `<button type="button" class="axis-option stereo-option ${item.id === selectedStereo ? "is-selected" : ""}" data-axis-index="${index}" data-value="${escapeHTML(item.id)}">${escapeHTML(item.label)}</button>`).join("")}
              </div>
            </div>
          </div>
          <div class="projection-scene">
            <div class="projection-surface" data-shape="${escapeHTML(selectedProjection === "360" ? "sphere" : selectedProjection.toLowerCase().includes("fish") ? "fisheye" : "hemisphere")}" aria-hidden="true"></div>
            <div class="projection-user" aria-hidden="true"></div>
          </div>
        </div>
      </div>
      <p class="causal-sentence">${escapeHTML(visual.shape)} <strong>${escapeHTML(visual.invariant)}</strong></p>
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
    const lanes = visual.lanes;
    return `
      <div class="branch-switch" aria-label="恢复路径">
        <button type="button" aria-pressed="true" data-life-branch="warm">同进程恢复</button>
        <button type="button" aria-pressed="false" data-life-branch="cold">进程被终止</button>
      </div>
      <div class="logic-figure lifecycle-figure">
        <svg class="desktop-logic" viewBox="0 0 980 390" role="img" aria-labelledby="life-title life-desc">
          <title id="life-title">${escapeHTML(action.label)}</title>
          <desc id="life-desc">Home View 关闭 Immersive Space；App 进程仍存在时由内存意图重建，进程终止时恢复意图同时消失并进入冷启动。</desc>
          <line x1="320" y1="45" x2="320" y2="350" stroke="var(--violet)" stroke-opacity=".34" stroke-dasharray="4 6"/>
          <text x="320" y="28" text-anchor="middle" class="tiny">HOME VIEW</text>
          <line x1="735" y1="45" x2="735" y2="350" stroke="var(--blue)" stroke-opacity=".2" stroke-dasharray="4 6"/>
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
              <text x="205" y="${y + 18}" class="tiny">${escapeHTML(lane.states.join(" → "))}</text>
              ${line}
              <circle cx="320" cy="${y}" r="5" fill="${index === 2 ? "var(--amber)" : index === 1 ? "var(--blue)" : "var(--violet)"}"/>
            `;
          }).join("")}
          <text x="468" y="196" class="small space-ended">旧 Space 已结束</text>
          <text x="746" y="196" class="small space-rebuilt">创建新 Space</text>
          <text x="425" y="306" class="small intent-memory">仅存在于当前进程内存</text>
          <g class="cold-only" opacity="0">
            <line x1="545" y1="64" x2="545" y2="342" stroke="var(--danger)" stroke-width="2"/>
            <text x="545" y="48" text-anchor="middle" fill="var(--danger)" font-size="10">PROCESS TERMINATED</text>
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
      <div class="lifecycle-model-detail">
        <span data-lifecycle-phases>${visual.warmPhases.map((phase) => escapeHTML(phase)).join(" → ")}</span>
        <strong>${escapeHTML(visual.invariant)}</strong>
      </div>
      ${renderBranches(action, demonstrationFor(action))}`;
  }

  function bindLifecycle(action) {
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
    const phases = stage.querySelector("[data-lifecycle-phases]");
    const visual = action.visual;
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
        phases.textContent = (isCold ? visual.coldPhases : visual.warmPhases).join(" → ");
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

  function actionSurfaces(action) {
    const ids = new Set((action.placements || []).map((placement) => placement.surfaceId));
    return [...ids]
      .map((id) => surfacesById.get(id))
      .filter((surface) => surface && !["behavior", "semantic-rule"].includes(surface.kind));
  }

  function renderBlueprint(action) {
    const actionSurfacesList = actionSurfaces(action);
    const ownerList = actionOwnerIds(action).map((id) => owners.get(id)).filter(Boolean);
    const surfaceNodes = actionSurfacesList.length
      ? actionSurfacesList.map((surface) => `
          <div class="blueprint-node blueprint-surface">
            <span>${escapeHTML(surface.kind === "system-world" ? "SYSTEM CONTEXT" : surface.kind === "spatial-world" ? "SCENE CONTAINER" : "UI SURFACE")}</span>
            <strong>${escapeHTML(surface.label)}</strong>
            <small>${escapeHTML(surface.summary || surface.description || "")}</small>
          </div>`).join("")
      : `<div class="blueprint-node blueprint-surface"><span>PRODUCT CONTRACT</span><strong>${escapeHTML(action.label)}</strong></div>`;
    const ownerNodes = ownerList.length
      ? ownerList.map((owner) => `
          <div class="blueprint-node blueprint-owner">
            <span>DOMAIN OWNER</span>
            <strong>${escapeHTML(owner.label || owner.id)}</strong>
            <small>${escapeHTML(owner.responsibility || "")}</small>
          </div>
          <div class="blueprint-node blueprint-boundary">
            <span>COMPILER BOUNDARY</span>
            <strong>${escapeHTML(owner.compilerBoundary || owner.boundary || "由 App Target 编译")}</strong>
          </div>`).join("")
      : `<div class="blueprint-node blueprint-owner"><span>OWNERSHIP</span><strong>尚未登记</strong></div>`;
    return `
      <div class="blueprint-figure" aria-label="${escapeHTML(action.label)} 系统承载与责任蓝图">
        <div class="blueprint-column">
          <p>WHERE · UI Surface / Scene Container / System Context</p>
          ${surfaceNodes}
        </div>
        <div class="blueprint-link" aria-hidden="true"><i></i><span>承载</span></div>
        <div class="blueprint-core">
          <span>PRODUCT ACTION</span>
          <strong>${escapeHTML(action.label)}</strong>
          <small>${escapeHTML(action.summary || "")}</small>
        </div>
        <div class="blueprint-link" aria-hidden="true"><i></i><span>拥有</span></div>
        <div class="blueprint-column">
          <p>WHO · 责任与边界</p>
          ${ownerNodes}
        </div>
      </div>`;
  }

  function stateSnapshot(label, patch, modifier = "", snapshotId = "", summaryDimensions = []) {
    const allValues = displayPatch(patch);
    const summaryPatch = summaryDimensions.length
      ? Object.fromEntries(summaryDimensions.filter((key) => key in patch).map((key) => [key, patch[key]]))
      : patch;
    const projectedValues = displayPatch(summaryPatch);
    const values = projectedValues.length ? projectedValues : allValues.slice(0, 3);
    return `
      <section class="machine-state ${modifier}">
        <span>STATE</span>
        <h3>${escapeHTML(label)}</h3>
        <div>${values.map((value) => `<b>${escapeHTML(value)}</b>`).join("") || "<b>合同状态保持不变</b>"}</div>
        ${allValues.length > values.length ? `<button type="button" data-machine-snapshot="${escapeHTML(snapshotId)}">查看全部 ${allValues.length} 项</button>` : ""}
      </section>`;
  }

  function renderStateMachine(action) {
    const demo = demonstrationFor(action);
    const demonstrations = action.demonstrations || [];
    const steps = demo.steps || [];
    const initialState = demo.initialState || {};
    const finalState = { ...initialState };
    steps.forEach((step) => Object.assign(finalState, step.patch || {}));
    const changedFinal = {};
    Object.keys(finalState).forEach((key) => {
      if (finalState[key] !== initialState[key]) changedFinal[key] = finalState[key];
    });
    const summaryDimensions = action.visualLayers.machine.summaryDimensions;
    return `
      <div class="machine-figure" aria-label="${escapeHTML(action.label)} 状态转换">
        ${demonstrations.length > 1 ? `
          <div class="demonstration-switch" aria-label="状态情境">
            ${demonstrations.map((item, index) => `<button type="button" data-demonstration-index="${index}" aria-pressed="${index === currentDemonstrationIndex}">${escapeHTML(item.label || `情境 ${index + 1}`)}</button>`).join("")}
          </div>` : ""}
        <div class="machine-track">
          ${stateSnapshot("稳定 · 操作前", initialState, "is-origin", "initial", summaryDimensions)}
          <div class="machine-arrow" aria-hidden="true"><i></i><span>BEGIN</span></div>
          <section class="machine-transaction">
            <span>TRANSITION TRANSACTION</span>
            <h3>${escapeHTML(action.causalSubject || action.label)}</h3>
            <div class="machine-phases">
              ${steps.map((step, index) => `
                <button type="button" data-machine-phase="${index}" aria-pressed="${index === 0}">
                  <i aria-hidden="true"></i><span>${escapeHTML(step.label || `阶段 ${index + 1}`)}</span>
                </button>`).join("") || `<span>无瞬态阶段</span>`}
            </div>
          </section>
          <div class="machine-arrow" aria-hidden="true"><i></i><span>COMMIT</span></div>
          ${stateSnapshot("稳定 · 操作后", changedFinal, "is-target", "final", summaryDimensions)}
        </div>
        ${(demo.branches || []).length ? `
          <div class="machine-branches" aria-label="状态分支">
            ${(demo.branches || []).map((item, index) => {
              const changes = (item.steps || []).reduce((count, step) => count + Object.keys(step.patch || {}).length, 0);
              const semanticLabel = {
                alternativeOutcome: "替代结果",
                guardedOutcome: "条件分支",
                recoverableFailure: "可恢复失败",
                rollback: "回滚",
                systemInterruption: "系统中断",
                unresolved: "尚未决策"
              }[item.visualSemantic];
              return `<button type="button" data-machine-branch="${index}" data-branch-semantic="${escapeHTML(item.visualSemantic)}">
                <span>${escapeHTML(semanticLabel)}</span>
                <strong>${escapeHTML(item.label || `分支 ${index + 1}`)}</strong>
                <small>${changes} 项状态变化</small>
              </button>`;
            }).join("")}
          </div>` : ""}
        <div class="machine-selected-detail" aria-live="polite">
          <span>当前过渡变化</span>
          <strong data-machine-phase-label>${escapeHTML(steps[0]?.label || "无瞬态阶段")} · ${displayPatch(steps[0]?.patch || {}).length} 项</strong>
          <div data-machine-phase-patch>${displayPatch(steps[0]?.patch || {}).map((item) => `<b>${escapeHTML(item)}</b>`).join("")}</div>
        </div>
        <div class="machine-contract">
          <span>合法转换由产品合同限定</span>
          <strong>${escapeHTML(action.explanation || action.summary || "")}</strong>
        </div>
      </div>`;
  }

  function bindStateMachine(action) {
    const demo = demonstrationFor(action);
    const steps = demo.steps || [];
    const label = stage.querySelector("[data-machine-phase-label]");
    const patch = stage.querySelector("[data-machine-phase-patch]");
    stage.querySelectorAll("[data-machine-phase]").forEach((button) => {
      button.addEventListener("click", () => {
        const index = Number(button.dataset.machinePhase);
        const step = steps[index];
        if (!step) return;
        stage.querySelectorAll("[data-machine-phase]").forEach((item) => item.setAttribute("aria-pressed", String(item === button)));
        const changes = displayPatch(step.patch || {});
        label.textContent = `${step.label || `阶段 ${index + 1}`} · ${changes.length} 项`;
        patch.innerHTML = changes.map((item) => `<b>${escapeHTML(item)}</b>`).join("");
      });
    });
    stage.querySelectorAll("[data-machine-snapshot]").forEach((button) => {
      button.addEventListener("click", () => {
        const isInitial = button.dataset.machineSnapshot === "initial";
        const initial = demo.initialState || {};
        const finalState = { ...initial };
        steps.forEach((step) => Object.assign(finalState, step.patch || {}));
        const selected = isInitial
          ? initial
          : Object.fromEntries(Object.entries(finalState).filter(([key, value]) => value !== initial[key]));
        const changes = displayPatch(selected);
        label.textContent = `${isInitial ? "完整操作前状态" : "完整操作后变化"} · ${changes.length} 项`;
        patch.innerHTML = changes.map((item) => `<b>${escapeHTML(item)}</b>`).join("");
      });
    });
    stage.querySelectorAll("[data-machine-branch]").forEach((button) => {
      button.addEventListener("click", () => {
        const branch = (demo.branches || [])[Number(button.dataset.machineBranch)];
        if (!branch) return;
        const branchPatch = {};
        (branch.steps || []).forEach((step) => Object.assign(branchPatch, step.patch || {}));
        const changes = displayPatch(branchPatch);
        label.textContent = `${branch.label || "分支"} · ${branch.visualSemantic} · ${changes.length} 项`;
        patch.innerHTML = changes.length
          ? changes.map((item) => `<b>${escapeHTML(item)}</b>`).join("")
          : `<b>${escapeHTML(branch.result || "该分支不改变已登记状态")}</b>`;
      });
    });
    stage.querySelectorAll("[data-demonstration-index]").forEach((button) => {
      button.addEventListener("click", () => {
        currentDemonstrationIndex = Number(button.dataset.demonstrationIndex);
        renderAction(action);
      });
    });
  }

  function renderLayerNavigation(action) {
    const configured = action.visualLayers || {};
    const levels = [
      { id: "journey", code: "A", label: "空间旅程", detail: "产品过程" },
      { id: "blueprint", code: "B", label: "系统蓝图", detail: "结构依据" },
      { id: "machine", code: "C", label: "状态机器", detail: "状态合同" }
    ];
    const supportedLevels = levels.filter((level) => configured[level.id]);
    const currentIndex = supportedLevels.findIndex((level) => level.id === currentActionLayer);
    const unavailableBlueprint = !configured.blueprint;
    const unavailableMachine = !configured.machine;
    return `
      <nav class="action-layer-nav" aria-label="${escapeHTML(action.label)} 解释深度">
        <p>解释深度 <span>产品过程 → 结构依据 → 状态合同</span></p>
        <div class="layer-depth-path">
          ${supportedLevels.map((level, index) => {
            const relation = index < currentIndex ? "ancestor" : index === currentIndex ? "current" : "deeper";
            const disabled = index > currentIndex + 1;
            return `
              ${index ? `<i aria-hidden="true"></i>` : ""}
              <button type="button" data-action-layer="${level.id}" data-depth-relation="${relation}" ${disabled ? "disabled" : ""} aria-current="${relation === "current" ? "step" : "false"}">
                <span>${level.code}</span>${escapeHTML(level.label)}<small>${escapeHTML(level.detail)}</small>
              </button>`;
          }).join("")}
        </div>
        ${unavailableBlueprint ? `<span class="layer-unavailable">B 不适用：该动作只登记在行为或语义规则中，没有 UI Surface / Scene Container 承载关系。</span>` : ""}
        ${unavailableMachine ? `<span class="layer-unavailable">C 不适用：该动作没有足以形成状态机器的非空状态变化或生命周期合同。</span>` : ""}
        ${currentIndex < supportedLevels.length - 1 ? `<button class="drill-deeper" type="button" data-action-layer="${supportedLevels[currentIndex + 1].id}">下钻：${escapeHTML(supportedLevels[currentIndex + 1].label)} →</button>` : `<span class="deepest-level">已到达该动作的最深合同层</span>`}
      </nav>`;
  }

  function renderAction(action) {
    const configuredLayers = action.visualLayers || {};
    if (!configuredLayers[currentActionLayer]) {
      currentActionLayer = configuredLayers.primary || "journey";
    }
    const grammar = action.visualGrammar;
    let figure;
    if (currentActionLayer === "blueprint") figure = renderBlueprint(action);
    else if (currentActionLayer === "machine") figure = renderStateMachine(action);
    else if (grammar === "spatial-transition") figure = spatialVisual(action);
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
    const layerKicker = {
      journey: "A · 产品过程",
      blueprint: "B · 结构依据",
      machine: "C · 状态合同"
    }[currentActionLayer];
    stage.innerHTML = `
      <a class="registry-jump" href="#action-search">浏览全部 ${actions.length} 项产品操作</a>
      <header class="journey-head">
        <div>
          <p class="section-kicker">${escapeHTML(layerKicker)}</p>
          <h2>${escapeHTML(action.label)}</h2>
          <p class="journey-summary">${escapeHTML(action.summary || action.description || "")}</p>
        </div>
        <span class="decision-badge ${isUnresolved(action) ? "unresolved" : ""}">${isUnresolved(action) ? "尚未决策" : "产品事实已确认"}</span>
      </header>
      ${renderLayerNavigation(action)}
      ${figure}
      ${currentActionLayer === "journey" ? `
        <div class="journey-explanation">
          <p class="causal-sentence">${escapeHTML(action.explanation || action.causalSummary || action.summary || "")}</p>
        </div>` : ""}
      ${currentActionLayer === "machine" ? `<div class="invariant-strip">${invariantLabels.map((label) => `<span class="invariant-chip">${escapeHTML(label)}</span>`).join("")}</div>` : ""}
      <div class="journey-meta">
        ${currentActionLayer === "blueprint" ? `<section class="meta-section"><h3>责任路径</h3><div class="responsibility-chain">${renderResponsibility(action)}</div></section>` : ""}
        <section class="meta-section delivery-only">
          <h3>交付状态</h3>
          <p>实现：${escapeHTML(deliveryLabel(implementation))}<br>验证：${escapeHTML(deliveryLabel(verification))}</p>
        </section>
        <section class="meta-section">
          <h3>一手来源</h3>
          <div class="source-buttons">${renderSourceButtons(sourceRefs)}</div>
        </section>
      </div>`;
    stage.querySelectorAll("[data-action-layer]").forEach((button) => {
      button.addEventListener("click", () => {
        currentActionLayer = button.dataset.actionLayer;
        renderAction(action);
        stage.focus({ preventScroll: true });
      });
    });
    bindSourceButtons(stage, sourceRefs);
    bindBranchButtons(action);
    if (currentActionLayer === "journey" && grammar === "spatial-transition") bindSpatial(action);
    if (currentActionLayer === "journey" && grammar === "format-to-space-transition") bindProjection();
    if (currentActionLayer === "journey" && grammar === "system-interruption") bindLifecycle(action);
    if (currentActionLayer === "machine") bindStateMachine(action);
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
    const snapshot = stateLandscape.snapshots.find((item) => item.id === currentLandscapeSnapshotId)
      || stateLandscape.snapshots[0];
    const applicableBranches = stateLandscape.branches
      .filter((branch) => branch.applicableSnapshotIds.includes(snapshot.id));
    const selectedBranch = applicableBranches
      .find((branch) => branch.id === currentLandscapeBranchId);
    const projectedState = { ...snapshot.state, ...(selectedBranch?.state || {}) };
    const projectedAnswers = { ...snapshot.answers, ...(selectedBranch?.answers || {}) };
    const projectedSourceRefs = [...(snapshot.sourceRefs || []), ...(selectedBranch?.sourceRefs || [])]
      .filter((ref, index, refs) =>
        refs.findIndex((candidate) =>
          candidate.sourceId === ref.sourceId && candidate.heading === ref.heading
        ) === index
      );
    const applicableShared = stateLandscape.sharedScopes
      .filter((scope) => scope.applicableSnapshotIds.includes(snapshot.id));
    const selectedLayer = snapshot.drilldown.find(
      (layer) => currentLandscapeFocus === `layer.${layer.id}`
    ) || snapshot.drilldown[0];
    const selectedShared = applicableShared.find(
      (scope) => currentLandscapeFocus === `shared.${scope.id}`
    );
    const focus = selectedShared || selectedLayer;

    function dimensionValues(dimension) {
      return (dimension.values || []).map((value) =>
        typeof value === "string" ? { id: value, label: value } : value
      );
    }

    function valueLabel(dimensionId, valueId) {
      const dimension = dimensions.get(dimensionId);
      return dimensionValues(dimension).find((value) => value.id === valueId)?.label || valueId;
    }

    function axisMarkup(dimensionId, selectedValue = null, compact = false) {
      const dimension = dimensions.get(dimensionId);
      return `
        <section class="landscape-axis${compact ? " is-compact" : ""}">
          <div>
            <h4>${escapeHTML(dimension.label)}</h4>
            <p>${escapeHTML(dimension.summary || dimension.description || "")}</p>
          </div>
          <div class="landscape-axis-values" aria-label="${escapeHTML(dimension.label)} 合法值">
            ${dimensionValues(dimension).map((value) => `
              <span${value.id === selectedValue ? ` aria-current="true"` : ""}>${escapeHTML(value.label || value.id)}</span>`).join("")}
          </div>
        </section>`;
    }

    function registryItemLabel(collection, id) {
      const item = collection.find((entry) => entry.id === id);
      return item?.label || item?.description || id;
    }

    const snapshotButton = (item) => `
      <button class="landscape-landmark shape-${escapeHTML(item.landmark.shape)}" type="button"
        data-landscape-snapshot="${escapeHTML(item.id)}"
        aria-pressed="${item.id === snapshot.id}">
        <span>${escapeHTML(item.label)}</span>
        <small>${escapeHTML(item.summary)}</small>
      </button>`;
    const snapshotFields = stateLandscape.fields.map((field) => `
      <section class="landscape-field" data-field="${escapeHTML(field.id)}">
        <header><strong>${escapeHTML(field.label)}</strong><small>${escapeHTML(field.summary)}</small></header>
        <div class="landscape-field-body">
          ${field.centerLabel ? `<span class="landscape-session-center">${escapeHTML(field.centerLabel)}</span>` : ""}
          ${field.snapshotIds.map((id) => snapshotButton(stateLandscape.snapshots.find((item) => item.id === id))).join("")}
        </div>
      </section>`).join("");
    const questionMarkup = stateLandscape.questions.map((question, index) => `
      <div>
        <dt><span>0${index + 1}</span>${escapeHTML(question.label)}</dt>
        <dd>${escapeHTML(projectedAnswers[question.id])}</dd>
      </div>`).join("");
    const currentFacts = Object.entries(projectedState).map(([dimensionId, valueId]) => `
      <div>
        <span>${escapeHTML(dimensions.get(dimensionId).label)}</span>
        <strong>${escapeHTML(valueLabel(dimensionId, valueId))}</strong>
      </div>`).join("");
    const drilldownButtons = snapshot.drilldown.map((layer, index) => `
      <button type="button" data-landscape-focus="layer.${escapeHTML(layer.id)}"
        aria-pressed="${!selectedShared && layer.id === selectedLayer.id}">
        <span>0${index + 1}</span>
        <strong>${escapeHTML(layer.label)}</strong>
        <small>${escapeHTML(layer.description)}</small>
      </button>`).join("");
    const focusDimensions = selectedShared
      ? selectedShared.dimensionIds
      : [...new Set([
          ...(selectedLayer.dimensionIds || []),
          ...(selectedLayer.id === "mechanism" ? Object.keys(selectedBranch?.state || {}) : [])
        ])];
    const focusMarkup = focusDimensions.length
      ? focusDimensions.map((dimensionId) => axisMarkup(
          dimensionId,
          projectedState[dimensionId],
          true
        )).join("")
      : `<p class="landscape-visible-result">${escapeHTML(focus.description)}</p>`;
    const relatedActionMarkup = (selectedShared?.relatedActionIds || []).map((actionId) => {
      const action = actionsById.get(actionId);
      return `<button class="source-link" type="button" data-landscape-action="${escapeHTML(actionId)}">转到产品行为 · ${escapeHTML(action?.label || actionId)}</button>`;
    }).join("");
    const branchButtons = applicableBranches.map((branch) => `
      <button type="button" data-landscape-branch="${escapeHTML(branch.id)}"
        data-branch-kind="${escapeHTML(branch.kind)}"
        aria-pressed="${branch.id === selectedBranch?.id}">
        <span>${escapeHTML(branch.kind)}</span>
        <strong>${escapeHTML(branch.label)}</strong>
      </button>`).join("");
    const branchDetail = selectedBranch ? `
      <section class="landscape-branch-detail">
        <header><span>${escapeHTML(selectedBranch.kind)}</span><h3>${escapeHTML(selectedBranch.label)}</h3></header>
        <p>${escapeHTML(selectedBranch.summary)}</p>
        <div>${Object.entries(selectedBranch.state).map(([dimensionId, valueId]) => `
          <span><b>${escapeHTML(dimensions.get(dimensionId).label)}</b>${escapeHTML(valueLabel(dimensionId, valueId))}</span>`).join("")}</div>
      </section>` : "";
    const sharedButtons = applicableShared.map((scope) => `
      <button type="button" data-landscape-focus="shared.${escapeHTML(scope.id)}"
        aria-pressed="${selectedShared?.id === scope.id}">
        <strong>${escapeHTML(scope.label)}</strong>
        <small>${escapeHTML(scope.summary)}</small>
      </button>`).join("");
    const contextualInvariantIds = new Set([
      ...(snapshot.invariantIds || []),
      ...(selectedBranch?.invariantIds || []),
      ...(selectedShared?.invariantIds || [])
    ]);
    const contextualConstraintIds = new Set([
      ...(snapshot.constraintIds || []),
      ...(selectedBranch?.constraintIds || [])
    ]);
    const referenceAxes = [...dimensions.values()]
      .map((dimension) => axisMarkup(dimension.id))
      .join("");

    target.innerHTML = `
      <section class="snapshot-landscape" aria-label="稳定产品快照">
        ${snapshotFields}
      </section>
      <section class="landscape-reading">
        <header>
          <span>${selectedBranch ? "BASE SNAPSHOT + APPLIED BRANCH" : "REPRESENTATIVE STABLE SNAPSHOT"}</span>
          <h3>${escapeHTML(snapshot.label)}${selectedBranch ? ` + ${escapeHTML(selectedBranch.label)}` : ""}</h3>
          <p>${escapeHTML(selectedBranch?.summary || snapshot.summary)}</p>
        </header>
        <dl class="landscape-questions">${questionMarkup}</dl>
        <div class="landscape-current-facts" aria-label="当前相关状态">${currentFacts}</div>
      </section>
      <section class="landscape-drilldown">
        <header>
          <span>从结果下钻</span>
          <p>当前只展开与 ${escapeHTML(snapshot.label)} 有关的状态；完整 Registry 仍有 ${dimensions.size} 个 dimensions。</p>
        </header>
        <nav>${drilldownButtons}</nav>
        <div class="landscape-focus">
          <header><h3>${escapeHTML(focus.label)}</h3><p>${escapeHTML(focus.summary || focus.description)}</p></header>
          <div>${focusMarkup}${relatedActionMarkup}</div>
        </div>
      </section>
      <section class="landscape-branches">
        <header><span>从此快照展开</span><p>临时、决策、失败、Ended 与系统中断只在适用的稳定场景下出现。</p></header>
        <div class="landscape-branch-fan">${branchButtons}</div>
        ${branchDetail}
      </section>
      <section class="landscape-shared">
        <header><span>共享状态范围</span><p>同一语义只登记一次，再说明它适用于哪些稳定快照。</p></header>
        <div>${sharedButtons}</div>
      </section>
      <section class="landscape-guardrails">
        <div>
          <span>此处必须保持</span>
          ${[...contextualInvariantIds].map((id) => `<p>${escapeHTML(registryItemLabel(stateRegistry.invariants || [], id))}</p>`).join("") || "<p>没有额外不变量。</p>"}
        </div>
        <div>
          <span>此处禁止组合</span>
          ${[...contextualConstraintIds].map((id) => `<p>${escapeHTML(registryItemLabel(stateRegistry.constraints || [], id))}</p>`).join("") || "<p>没有额外禁止组合。</p>"}
        </div>
      </section>
      <div class="landscape-sources">${renderSourceButtons(projectedSourceRefs)}</div>
      <details class="landscape-reference">
        <summary>
          <span>REFERENCE LAYER</span>
          <strong>${escapeHTML(stateLandscape.reference.label)}</strong>
          <small>${dimensions.size} dimensions · 展开正式状态轴与全部合法 values</small>
        </summary>
        <div>${referenceAxes}</div>
      </details>`;

    target.querySelectorAll("[data-landscape-snapshot]").forEach((button) => {
      button.addEventListener("click", () => {
        currentLandscapeSnapshotId = button.dataset.landscapeSnapshot;
        currentLandscapeBranchId = null;
        currentLandscapeFocus = "layer.visible";
        renderStates();
      });
    });
    target.querySelectorAll("[data-landscape-focus]").forEach((button) => {
      button.addEventListener("click", () => {
        currentLandscapeFocus = button.dataset.landscapeFocus;
        renderStates();
      });
    });
    target.querySelectorAll("[data-landscape-branch]").forEach((button) => {
      button.addEventListener("click", () => {
        currentLandscapeBranchId = currentLandscapeBranchId === button.dataset.landscapeBranch
          ? null
          : button.dataset.landscapeBranch;
        renderStates();
      });
    });
    target.querySelectorAll("[data-landscape-action]").forEach((button) => {
      button.addEventListener("click", () => openAction(button.dataset.landscapeAction));
    });
    bindSourceButtons(target.querySelector(".landscape-sources"), projectedSourceRefs);
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
    switchView(initialView, false);

    const themeButton = document.getElementById("toggle-theme");
    const themeLabel = document.getElementById("theme-label");
    const themeMedia = matchMedia("(prefers-color-scheme: dark)");
    const themeNames = { system: "跟随系统", light: "白天", dark: "暗夜" };
    const applyTheme = (preference) => {
      const resolved = preference === "system" ? (themeMedia.matches ? "dark" : "light") : preference;
      document.documentElement.dataset.theme = resolved;
      document.documentElement.dataset.themePreference = preference;
      themeLabel.textContent = themeNames[preference];
      localStorage.setItem("atlas-theme", preference);
    };
    applyTheme(document.documentElement.dataset.themePreference || "system");
    themeButton.addEventListener("click", () => {
      const current = document.documentElement.dataset.themePreference || "system";
      const next = current === "system" ? "light" : current === "light" ? "dark" : "system";
      applyTheme(next);
    });
    themeMedia.addEventListener("change", () => {
      if (document.documentElement.dataset.themePreference === "system") applyTheme("system");
    });

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

    renderActionIndex();
    if (currentActionId) renderAction(actionsById.get(currentActionId));
    else stage.innerHTML = `<p class="journey-summary">Product Action Registry 为空。</p>`;
    document.getElementById("source-status").textContent = `${sources.size} 份一手来源 · ${actions.length} 项产品操作`;
  }

  init();
})();
