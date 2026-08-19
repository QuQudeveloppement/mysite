/* ==========================================================================
   admin.js — interface d'administration du blog.
   Fonctionne sans serveur : lit/écrit directement dans le dépôt GitHub
   via l'API REST (Contents API), authentifiée par un token personnel.
   ========================================================================== */

const SESSION_KEY = "atelier_admin_session";
const ARTICLES_PATH = "articles.json";

let session = null;      // { owner, repo, branch, token }
let articles = [];        // tableau en mémoire
let articlesSha = null;   // sha du fichier articles.json (nécessaire pour écrire)
let editingId = null;     // id de l'article en cours d'édition (null = nouveau)
let blocks = [];          // blocs de l'article en cours d'édition

/* -------------------------------------------------------------------- */
/*  Utilitaires encodage / API GitHub                                   */
/* -------------------------------------------------------------------- */

function b64EncodeUnicode(str) {
  return btoa(unescape(encodeURIComponent(str)));
}
function b64DecodeUnicode(str) {
  return decodeURIComponent(escape(atob(str.replace(/\n/g, ""))));
}

function ghHeaders() {
  return {
    "Authorization": `token ${session.token}`,
    "Accept": "application/vnd.github+json"
  };
}

function ghUrl(path) {
  return `https://api.github.com/repos/${session.owner}/${session.repo}/contents/${path}`;
}

// Récupère un fichier texte du dépôt. Renvoie { sha, text } ou null si absent.
async function ghGetFile(path) {
  const res = await fetch(`${ghUrl(path)}?ref=${encodeURIComponent(session.branch)}&t=${Date.now()}`, {
    headers: ghHeaders()
  });
  if (res.status === 404) return null;
  if (!res.ok) throw new Error(`Lecture impossible (${res.status})`);
  const data = await res.json();
  return { sha: data.sha, text: b64DecodeUnicode(data.content) };
}

// Écrit un fichier texte (créé ou met à jour). sha requis si le fichier existe déjà.
async function ghPutTextFile(path, text, message, sha) {
  const body = {
    message,
    content: b64EncodeUnicode(text),
    branch: session.branch
  };
  if (sha) body.sha = sha;
  const res = await fetch(ghUrl(path), {
    method: "PUT",
    headers: { ...ghHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.message || `Écriture impossible (${res.status})`);
  }
  return res.json();
}

// Écrit un fichier binaire (image) déjà en base64 brut (sans préfixe data:...).
async function ghPutBinaryFile(path, base64Data, message) {
  const body = { message, content: base64Data, branch: session.branch };
  const res = await fetch(ghUrl(path), {
    method: "PUT",
    headers: { ...ghHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify(body)
  });
  if (!res.ok) {
    const err = await res.json().catch(() => ({}));
    throw new Error(err.message || `Envoi de l'image impossible (${res.status})`);
  }
  const data = await res.json();
  return data.content.download_url || data.content.path;
}

function fileToBase64(file) {
  return new Promise((resolve, reject) => {
    const reader = new FileReader();
    reader.onload = () => resolve(reader.result.split(",")[1]);
    reader.onerror = () => reject(new Error("Lecture du fichier impossible"));
    reader.readAsDataURL(file);
  });
}

function slugify(str) {
  return str
    .normalize("NFD").replace(/[\u0300-\u036f]/g, "")
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/(^-|-$)/g, "") || "article";
}

function uniqueSlug(base, excludeId) {
  let slug = base, i = 2;
  const taken = new Set(articles.filter(a => a.id !== excludeId).map(a => a.id));
  while (taken.has(slug)) { slug = `${base}-${i++}`; }
  return slug;
}

/* -------------------------------------------------------------------- */
/*  Écrans / état                                                       */
/* -------------------------------------------------------------------- */

const $ = sel => document.querySelector(sel);

function showStatus(el, message, kind) {
  el.textContent = message;
  el.className = `status-line ${kind}`;
  el.hidden = false;
}
function hideStatus(el) { el.hidden = true; }

function restoreSession() {
  const raw = sessionStorage.getItem(SESSION_KEY);
  if (!raw) return false;
  try { session = JSON.parse(raw); return true; } catch { return false; }
}
function persistSession() {
  sessionStorage.setItem(SESSION_KEY, JSON.stringify(session));
}
function clearSession() {
  sessionStorage.removeItem(SESSION_KEY);
  session = null;
}

async function tryLogin(owner, repo, branch, token) {
  session = { owner, repo, branch: branch || "main", token };
  const file = await ghGetFile(ARTICLES_PATH); // vérifie l'accès + récupère les données
  if (file) {
    articlesSha = file.sha;
    articles = JSON.parse(file.text);
  } else {
    // Le fichier n'existe pas encore : on le crée au premier enregistrement.
    articlesSha = null;
    articles = [];
  }
  persistSession();
}

/* -------------------------------------------------------------------- */
/*  Rendu : écran de connexion                                          */
/* -------------------------------------------------------------------- */

function renderLogin() {
  $("#login-screen").hidden = false;
  $("#dashboard-screen").hidden = true;
  $("#editor-screen").hidden = true;
}

/* -------------------------------------------------------------------- */
/*  Rendu : tableau de bord (liste des articles)                        */
/* -------------------------------------------------------------------- */

function renderDashboard() {
  $("#login-screen").hidden = true;
  $("#dashboard-screen").hidden = false;
  $("#editor-screen").hidden = true;

  $("#session-label").textContent = `${session.owner}/${session.repo} (${session.branch})`;

  const list = $("#article-admin-list");
  const sorted = [...articles].sort((a, b) => (a.date < b.date ? 1 : -1));
  if (sorted.length === 0) {
    list.innerHTML = `<p class="log-empty">Aucun article pour l'instant. Crée le premier.</p>`;
    return;
  }
  list.innerHTML = sorted.map(a => `
    <div class="card" style="margin-bottom:14px;display:flex;align-items:center;justify-content:space-between;gap:12px;flex-wrap:wrap;">
      <div>
        <div class="log-date">${formatDate(a.date)}</div>
        <div style="font-family:var(--font-display);margin-top:4px;">${escapeHtml(a.title)}</div>
      </div>
      <div style="display:flex;gap:8px;">
        <button class="btn" data-edit="${a.id}">Modifier</button>
        <button class="btn btn-danger" data-delete="${a.id}">Supprimer</button>
      </div>
    </div>
  `).join("");

  list.querySelectorAll("[data-edit]").forEach(btn => {
    btn.addEventListener("click", () => openEditor(btn.dataset.edit));
  });
  list.querySelectorAll("[data-delete]").forEach(btn => {
    btn.addEventListener("click", () => deleteArticle(btn.dataset.delete));
  });
}

async function deleteArticle(id) {
  const article = articles.find(a => a.id === id);
  if (!article) return;
  if (!confirm(`Supprimer définitivement « ${article.title} » ?`)) return;

  const statusEl = $("#dashboard-status");
  try {
    articles = articles.filter(a => a.id !== id);
    const result = await ghPutTextFile(
      ARTICLES_PATH,
      JSON.stringify(articles, null, 2),
      `Suppression: ${article.title}`,
      articlesSha
    );
    articlesSha = result.content.sha;
    showStatus(statusEl, "Article supprimé.", "ok");
    renderDashboard();
  } catch (e) {
    showStatus(statusEl, `Erreur : ${e.message}`, "err");
  }
}

/* -------------------------------------------------------------------- */
/*  Rendu : éditeur d'article                                           */
/* -------------------------------------------------------------------- */

function openEditor(id) {
  editingId = id || null;
  const article = editingId ? articles.find(a => a.id === editingId) : null;

  $("#login-screen").hidden = true;
  $("#dashboard-screen").hidden = true;
  $("#editor-screen").hidden = false;

  $("#editor-title-label").textContent = article ? "Modifier l'article" : "Nouvel article";
  $("#f-title").value = article ? article.title : "";
  $("#f-date").value = article ? article.date : new Date().toISOString().slice(0, 10);
  $("#f-excerpt").value = article ? article.excerpt || "" : "";
  $("#f-cover").value = article ? article.cover || "" : "";
  blocks = article ? JSON.parse(JSON.stringify(article.blocks || [])) : [];

  hideStatus($("#editor-status"));
  renderBlocksEditor();
  renderPreview();
}

function renderBlocksEditor() {
  const wrap = $("#blocks-list");
  if (blocks.length === 0) {
    wrap.innerHTML = `<p class="log-empty">Aucun bloc. Ajoute du texte, une image ou une vidéo ci-dessous.</p>`;
    return;
  }
  wrap.innerHTML = blocks.map((b, i) => blockEditorHtml(b, i)).join("");

  wrap.querySelectorAll("[data-up]").forEach(btn => btn.addEventListener("click", () => moveBlock(+btn.dataset.up, -1)));
  wrap.querySelectorAll("[data-down]").forEach(btn => btn.addEventListener("click", () => moveBlock(+btn.dataset.down, 1)));
  wrap.querySelectorAll("[data-remove]").forEach(btn => btn.addEventListener("click", () => {
    blocks.splice(+btn.dataset.remove, 1);
    renderBlocksEditor(); renderPreview();
  }));
  wrap.querySelectorAll("[data-field]").forEach(input => {
    input.addEventListener("input", () => {
      const [idx, field] = input.dataset.field.split(":");
      blocks[+idx][field] = input.value;
      renderPreview();
    });
  });
  wrap.querySelectorAll("[data-image-upload]").forEach(input => {
    input.addEventListener("change", (e) => handleBlockImageUpload(e, +input.dataset.imageUpload));
  });
}

function blockEditorHtml(b, i) {
  const controls = `
    <div style="display:flex;gap:6px;">
      <button type="button" class="btn btn-ghost" data-up="${i}" title="Monter">↑</button>
      <button type="button" class="btn btn-ghost" data-down="${i}" title="Descendre">↓</button>
      <button type="button" class="btn btn-danger" data-remove="${i}" title="Supprimer">✕</button>
    </div>`;

  if (b.type === "heading") {
    return `<div class="card" style="margin-bottom:12px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span class="badge">Titre de section</span>${controls}
      </div>
      <div class="field" style="margin-top:10px;">
        <input type="text" data-field="${i}:value" value="${escapeHtml(b.value || "")}" placeholder="Titre de section">
      </div>
    </div>`;
  }
  if (b.type === "text") {
    return `<div class="card" style="margin-bottom:12px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span class="badge">Texte</span>${controls}
      </div>
      <div class="field" style="margin-top:10px;">
        <textarea data-field="${i}:value" placeholder="Texte du paragraphe (**gras**, *italique*)">${escapeHtml(b.value || "")}</textarea>
      </div>
    </div>`;
  }
  if (b.type === "code") {
    return `<div class="card" style="margin-bottom:12px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span class="badge">Code</span>${controls}
      </div>
      <div class="field" style="margin-top:10px;">
        <textarea data-field="${i}:value" placeholder="Extrait de code">${escapeHtml(b.value || "")}</textarea>
      </div>
    </div>`;
  }
  if (b.type === "image") {
    return `<div class="card" style="margin-bottom:12px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span class="badge">Image</span>${controls}
      </div>
      <div class="field" style="margin-top:10px;">
        <label>Fichier à envoyer dans le dépôt (ou laisse vide et colle une URL ci-dessous)</label>
        <input type="file" accept="image/*" data-image-upload="${i}">
      </div>
      <div class="field">
        <label>URL de l'image</label>
        <input type="text" data-field="${i}:url" value="${escapeHtml(b.url || "")}" placeholder="images/photo.jpg ou https://...">
      </div>
      <div class="field">
        <label>Légende (optionnelle)</label>
        <input type="text" data-field="${i}:caption" value="${escapeHtml(b.caption || "")}">
      </div>
    </div>`;
  }
  if (b.type === "video") {
    return `<div class="card" style="margin-bottom:12px;">
      <div style="display:flex;justify-content:space-between;align-items:center;">
        <span class="badge">Vidéo</span>${controls}
      </div>
      <div class="field" style="margin-top:10px;">
        <label>URL (YouTube, Vimeo, ou lien direct .mp4)</label>
        <input type="text" data-field="${i}:url" value="${escapeHtml(b.url || "")}" placeholder="https://youtube.com/watch?v=...">
      </div>
      <div class="field">
        <label>Légende (optionnelle)</label>
        <input type="text" data-field="${i}:caption" value="${escapeHtml(b.caption || "")}">
      </div>
    </div>`;
  }
  return "";
}

function moveBlock(index, dir) {
  const target = index + dir;
  if (target < 0 || target >= blocks.length) return;
  [blocks[index], blocks[target]] = [blocks[target], blocks[index]];
  renderBlocksEditor();
  renderPreview();
}

async function handleBlockImageUpload(e, index) {
  const file = e.target.files[0];
  if (!file) return;
  const statusEl = $("#editor-status");
  showStatus(statusEl, "Envoi de l'image en cours…", "ok");
  try {
    const base64 = await fileToBase64(file);
    const safeName = `${Date.now()}-${slugify(file.name.replace(/\.[^.]+$/, ""))}${(file.name.match(/\.[^.]+$/) || [""])[0]}`;
    const path = `images/${safeName}`;
    await ghPutBinaryFile(path, base64, `Ajout image: ${safeName}`);
    blocks[index].url = path;
    hideStatus(statusEl);
    renderBlocksEditor();
    renderPreview();
  } catch (err) {
    showStatus(statusEl, `Erreur d'envoi : ${err.message}`, "err");
  }
}

function addBlock(type) {
  blocks.push({ type, value: "", url: "", caption: "" });
  renderBlocksEditor();
  renderPreview();
}

function renderPreview() {
  const title = $("#f-title").value || "(sans titre)";
  const date = $("#f-date").value || "";
  const preview = $("#editor-preview");
  preview.innerHTML = `
    <header class="article-header">
      <span class="log-date">${date ? formatDate(date) : ""}</span>
      <h1>${escapeHtml(title)}</h1>
    </header>
    <div>${blocks.map(renderBlock).join("")}</div>
  `;
}

async function saveArticle() {
  const statusEl = $("#editor-status");
  const title = $("#f-title").value.trim();
  const date = $("#f-date").value;
  if (!title) { showStatus(statusEl, "Le titre est obligatoire.", "err"); return; }
  if (!date) { showStatus(statusEl, "La date est obligatoire.", "err"); return; }

  const id = editingId || uniqueSlug(slugify(title));
  const articleData = {
    id,
    title,
    date,
    excerpt: $("#f-excerpt").value.trim(),
    cover: $("#f-cover").value.trim(),
    blocks
  };

  const idx = articles.findIndex(a => a.id === id);
  if (idx >= 0) articles[idx] = articleData; else articles.push(articleData);

  showStatus(statusEl, "Enregistrement…", "ok");
  try {
    const result = await ghPutTextFile(
      ARTICLES_PATH,
      JSON.stringify(articles, null, 2),
      `${editingId ? "Modification" : "Publication"}: ${title}`,
      articlesSha
    );
    articlesSha = result.content.sha;
    editingId = id;
    showStatus(statusEl, "Article enregistré et publié.", "ok");
    setTimeout(() => renderDashboard(), 500);
  } catch (e) {
    showStatus(statusEl, `Erreur : ${e.message}`, "err");
  }
}

/* -------------------------------------------------------------------- */
/*  Câblage des événements                                              */
/* -------------------------------------------------------------------- */

document.addEventListener("DOMContentLoaded", () => {
  if (restoreSession()) {
    ghGetFile(ARTICLES_PATH)
      .then(file => {
        if (file) { articlesSha = file.sha; articles = JSON.parse(file.text); }
        renderDashboard();
      })
      .catch(() => { clearSession(); renderLogin(); });
  } else {
    renderLogin();
  }

  $("#login-form").addEventListener("submit", async (e) => {
    e.preventDefault();
    const statusEl = $("#login-status");
    showStatus(statusEl, "Connexion en cours…", "ok");
    try {
      await tryLogin(
        $("#f-owner").value.trim(),
        $("#f-repo").value.trim(),
        $("#f-branch").value.trim(),
        $("#f-token").value.trim()
      );
      hideStatus(statusEl);
      renderDashboard();
    } catch (err) {
      showStatus(statusEl, `Connexion refusée : ${err.message}`, "err");
    }
  });

  $("#btn-logout").addEventListener("click", () => { clearSession(); renderLogin(); });
  $("#btn-new-article").addEventListener("click", () => openEditor(null));
  $("#btn-back-dashboard").addEventListener("click", () => renderDashboard());

  $("#f-title").addEventListener("input", renderPreview);
  $("#f-date").addEventListener("input", renderPreview);

  $("#btn-add-heading").addEventListener("click", () => addBlock("heading"));
  $("#btn-add-text").addEventListener("click", () => addBlock("text"));
  $("#btn-add-image").addEventListener("click", () => addBlock("image"));
  $("#btn-add-video").addEventListener("click", () => addBlock("video"));
  $("#btn-add-code").addEventListener("click", () => addBlock("code"));

  $("#btn-save-article").addEventListener("click", saveArticle);
});
